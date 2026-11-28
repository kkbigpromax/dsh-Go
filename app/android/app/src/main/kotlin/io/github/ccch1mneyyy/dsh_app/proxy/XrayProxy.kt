package io.github.ccch1mneyyy.dsh_app.proxy

import android.content.Context
import android.net.ConnectivityManager
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.util.Base64
import java.io.Closeable
import java.io.File
import java.io.IOException
import java.security.SecureRandom
import java.util.ArrayDeque
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * The bundled Xray core ([BINARY], runtime/xray) as this app's own proxy, for the engine only.
 *
 * Nothing about it is system-wide: no VPN, no system proxy setting, no TCP port. The core
 * listens on an abstract Unix socket with a random name and random credentials, fresh
 * for every launch; Android keeps another app's processes from connecting to it, and the
 * credentials stop anything that reaches it anyway. Its configuration goes in through
 * stdin and never touches the disk.
 *
 * One process per engine launch: [startForEngine] before DSH starts, [close] when it exits
 * (RuntimeController). The process is a child of the app, so it also goes when the system
 * kills the app's process group.
 */
class XrayProxy private constructor(
    private val process: Process,
    private val socket: String,
    private val auth: Pair<String, String>,
    private val tail: ArrayDeque<String>,
) : Closeable {

    /** The engine's environment additions; [nodeOptions] is what the launch already has. */
    fun engineEnv(nodeOptions: String?): Map<String, String> =
        ProxyConfig.engineEnv(10_000 + random.nextInt(50_000), socket, auth, nodeOptions)

    override fun close() {
        process.destroy()
        if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly()
    }

    companion object {
        /** A plain name: what the core is shows in no file name. */
        const val BINARY = "libnetcore.so"
        private const val PREFS = "proxy"
        private val random = SecureRandom()
        private const val KEY = "config"
        private const val READY_MS = 5_000L
        private const val TAIL_LINES = 20

        /** What the last engine launch did with the proxy, for the settings page. */
        @Volatile var lastError: String? = null
            private set
        @Volatile var running: XrayProxy? = null
            private set

        fun binary(context: Context) = File(context.applicationInfo.nativeLibraryDir, BINARY)

        fun available(context: Context) = binary(context).canExecute()

        fun load(context: Context): ProxyConfig = ProxyConfig.fromJson(
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
                ?.let { runCatching { JSONObject(it) }.getOrNull() },
        )

        fun save(context: Context, config: ProxyConfig) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, config.toJson().toString()).apply()
        }

        /**
         * For an engine launch: the running proxy, or null when it is off. When it is on
         * but cannot start, the reason goes to [log] and the engine starts without it
         * (the settings page shows [lastError]).
         */
        fun startForEngine(context: Context, log: (String) -> Unit): XrayProxy? {
            val config = load(context)
            lastError = null
            if (!config.enabled) return null
            return try {
                launch(context, config).also { running = it }
            } catch (e: Exception) {
                lastError = e.message ?: e.javaClass.simpleName
                log("[dsh-app] proxy not started: $lastError; the engine connects directly")
                null
            }
        }

        fun engineStopped(proxy: XrayProxy?) {
            proxy?.close()
            if (running === proxy) running = null
        }

        /**
         * Connects through [config] once without saving it: a temporary core, one request
         * for [TEST_HOST]'s generate_204 sent over the core's socket. Returns the time in ms;
         * throws with the reason.
         */
        fun test(context: Context, config: ProxyConfig): Long = launch(context, config).use { proxy ->
            val started = System.nanoTime()
            val status = try {
                proxy.open().use { local ->
                    local.soTimeout = 10_000
                    val credentials = Base64.encodeToString("${proxy.auth.first}:${proxy.auth.second}".toByteArray(), Base64.NO_WRAP)
                    local.outputStream.write(
                        ("GET http://$TEST_HOST/generate_204 HTTP/1.1\r\nHost: $TEST_HOST\r\n" +
                            "Proxy-Authorization: Basic $credentials\r\nConnection: close\r\n\r\n").toByteArray(),
                    )
                    local.outputStream.flush()
                    local.inputStream.bufferedReader().readLine().orEmpty()
                }
            } catch (e: IOException) {
                throw IllegalStateException(proxy.reason() ?: e.message ?: e.javaClass.simpleName)
            }
            val code = status.split(' ').getOrNull(1)?.toIntOrNull()
            if (code == null || code !in 200..399) throw IllegalStateException(proxy.reason() ?: status.ifEmpty { "no answer" })
            (System.nanoTime() - started) / 1_000_000
        }

        const val TEST_HOST = "www.gstatic.com"

        private fun token(bytes: Int) = ByteArray(bytes).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }

        private fun launch(context: Context, config: ProxyConfig): XrayProxy {
            config.problem()?.let { throw IllegalArgumentException("invalid $it") }
            val binary = binary(context)
            if (!binary.canExecute()) throw IllegalStateException("the proxy core is missing from this build")
            val socket = token(12)
            val auth = token(12) to token(16)
            val process = ProcessBuilder(binary.absolutePath, "run", "-c", "stdin:")
                .directory(context.noBackupFilesDir)
                .redirectErrorStream(true)
                .start()
            process.outputStream.use { it.write(config.xray(socket, auth, dns(context)).toString().toByteArray()) }
            val tail = ArrayDeque<String>()
            Thread({
                process.inputStream.bufferedReader().forEachLine { line ->
                    synchronized(tail) {
                        tail.addLast(line)
                        while (tail.size > TAIL_LINES) tail.removeFirst()
                    }
                }
            }, "xray-log").apply { isDaemon = true }.start()
            val proxy = XrayProxy(process, socket, auth, tail)
            val deadline = System.currentTimeMillis() + READY_MS
            while (true) {
                if (!process.isAlive) throw IllegalStateException(proxy.reason() ?: "the proxy core exited (${process.exitValue()})")
                val listening = try {
                    proxy.open().close()
                    true
                } catch (_: IOException) {
                    false
                }
                if (listening) return proxy
                if (System.currentTimeMillis() > deadline) {
                    proxy.close()
                    throw IllegalStateException("the proxy core did not start listening")
                }
                Thread.sleep(100)
            }
        }

        /** The phone's resolvers for the server's own name, then public ones. */
        private fun dns(context: Context): List<String> {
            val phone = runCatching {
                val cm = context.getSystemService(ConnectivityManager::class.java)
                cm.getLinkProperties(cm.activeNetwork)?.dnsServers?.mapNotNull { it.hostAddress } ?: emptyList()
            }.getOrDefault(emptyList())
            return (phone + ProxyConfig.FALLBACK_DNS).distinct()
        }
    }

    /** A connection to the core's abstract socket. */
    private fun open(): LocalSocket = LocalSocket().apply {
        try {
            connect(LocalSocketAddress(socket, LocalSocketAddress.Namespace.ABSTRACT))
        } catch (e: IOException) {
            close()
            throw e
        }
    }

    /** Xray's last warning or error line, the likeliest reason for a failure. */
    private fun reason(): String? = synchronized(tail) {
        tail.lastOrNull { it.contains("[Warning]") || it.contains("[Error]") || it.contains("Failed") } ?: tail.lastOrNull()
    }
}
