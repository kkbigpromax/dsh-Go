package io.github.ccch1mneyyy.dsh_app.proxy

import android.content.Context
import android.net.ConnectivityManager
import java.io.Closeable
import java.io.File
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.util.ArrayDeque
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/**
 * The bundled Xray core (libxray.so, runtime/xray) as a local HTTP proxy for the engine.
 *
 * One process per engine launch: [start] before DSH starts, [close] when it exits
 * (RuntimeController). The process is a child of the app, so it also goes when the
 * system kills the app's process group. A fresh loopback port each time: nothing to clean up.
 */
class XrayProxy private constructor(
    private val process: Process,
    val port: Int,
    private val tail: ArrayDeque<String>,
) : Closeable {

    val env: Map<String, String> get() = ProxyConfig.engineEnv(port)

    override fun close() {
        process.destroy()
        if (!process.waitFor(2, TimeUnit.SECONDS)) process.destroyForcibly()
    }

    companion object {
        private const val PREFS = "proxy"
        private const val KEY = "config"
        private const val READY_MS = 5_000L
        private const val TAIL_LINES = 20

        /** What the last engine launch did with the proxy, for the settings page. */
        @Volatile var lastError: String? = null
            private set
        @Volatile var running: XrayProxy? = null
            private set

        fun binary(context: Context) = File(context.applicationInfo.nativeLibraryDir, "libxray.so")

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
         * to [TEST_URL]. Returns the time in ms; throws with the reason.
         */
        fun test(context: Context, config: ProxyConfig): Long = launch(context, config).use { proxy ->
            val started = System.nanoTime()
            val connection = URL(TEST_URL).openConnection(Proxy(Proxy.Type.HTTP, InetSocketAddress(ProxyConfig.LOOPBACK, proxy.port))) as HttpURLConnection
            connection.connectTimeout = 10_000
            connection.readTimeout = 10_000
            try {
                val code = connection.responseCode
                if (code !in 200..399) throw IllegalStateException("HTTP $code")
            } catch (e: java.io.IOException) {
                throw IllegalStateException(proxy.reason() ?: e.message ?: e.javaClass.simpleName)
            } finally {
                connection.disconnect()
            }
            (System.nanoTime() - started) / 1_000_000
        }

        const val TEST_URL = "https://www.gstatic.com/generate_204"

        private fun launch(context: Context, config: ProxyConfig): XrayProxy {
            config.problem()?.let { throw IllegalArgumentException("invalid $it") }
            val binary = binary(context)
            if (!binary.canExecute()) throw IllegalStateException("libxray.so missing from this build")
            val port = ServerSocket(0, 1, java.net.InetAddress.getByName(ProxyConfig.LOOPBACK)).use { it.localPort }
            val dir = File(context.noBackupFilesDir, "xray").apply { mkdirs() }
            // Private to the app; holds the server's credentials.
            val file = File(dir, "config-$port.json")
            file.writeText(config.xray(port, dns(context)).toString())
            val process = ProcessBuilder(binary.absolutePath, "run", "-c", file.absolutePath)
                .directory(dir)
                .redirectErrorStream(true)
                .start()
            val tail = ArrayDeque<String>()
            Thread({
                process.inputStream.bufferedReader().forEachLine { line ->
                    synchronized(tail) {
                        tail.addLast(line)
                        while (tail.size > TAIL_LINES) tail.removeFirst()
                    }
                }
            }, "xray-log").apply { isDaemon = true }.start()
            val proxy = XrayProxy(process, port, tail)
            val deadline = System.currentTimeMillis() + READY_MS
            while (true) {
                if (!process.isAlive) {
                    file.delete()
                    throw IllegalStateException(proxy.reason() ?: "xray exited (${process.exitValue()})")
                }
                val listening = try {
                    Socket().use { it.connect(InetSocketAddress(ProxyConfig.LOOPBACK, port), 200); true }
                } catch (_: java.io.IOException) {
                    false
                }
                if (listening) break
                if (System.currentTimeMillis() > deadline) {
                    proxy.close()
                    file.delete()
                    throw IllegalStateException("xray did not start listening")
                }
                Thread.sleep(100)
            }
            // Xray has read it; the credentials need not stay on disk.
            file.delete()
            return proxy
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

    /** Xray's last warning or error line, the likeliest reason for a failure. */
    private fun reason(): String? = synchronized(tail) {
        tail.lastOrNull { it.contains("[Warning]") || it.contains("[Error]") || it.contains("Failed") } ?: tail.lastOrNull()
    }
}
