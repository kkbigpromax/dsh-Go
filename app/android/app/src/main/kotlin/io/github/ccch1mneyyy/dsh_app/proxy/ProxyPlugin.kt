package io.github.ccch1mneyyy.dsh_app.proxy

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * `dsh/proxy` for 设置 › 代理:
 * - `load` → {config, available, running, error}
 * - `save` {config} → null, or the field that is wrong
 * - `test` {config} → {ms} or {error}; never saves
 */
class ProxyPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "dsh-proxy").apply { isDaemon = true } }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val app = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dsh/proxy").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "load" -> result.success(state(app))
                    "save" -> {
                        val config = parse(call.arguments)
                        val problem = if (config.enabled) config.problem() else null
                        if (problem == null) XrayProxy.save(app, config)
                        result.success(problem)
                    }
                    "test" -> {
                        val config = parse(call.arguments)
                        worker.execute {
                            val answer: Map<String, Any?> = try {
                                mapOf("ms" to XrayProxy.test(app, config))
                            } catch (e: Exception) {
                                mapOf("error" to (e.message ?: e.javaClass.simpleName))
                            }
                            main.post { result.success(answer) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun state(app: Context): Map<String, Any?> = mapOf(
        "config" to XrayProxy.load(app).toJson().toString(),
        "available" to XrayProxy.available(app),
        "running" to (XrayProxy.running != null),
        "error" to XrayProxy.lastError,
    )

    private fun parse(arguments: Any?): ProxyConfig =
        ProxyConfig.fromJson((arguments as? String)?.let { runCatching { JSONObject(it) }.getOrNull() })
}
