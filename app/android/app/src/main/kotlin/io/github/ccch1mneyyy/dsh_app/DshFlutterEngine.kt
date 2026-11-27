package io.github.ccch1mneyyy.dsh_app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.github.ccch1mneyyy.dsh_app.files.FilesPlugin
import io.github.ccch1mneyyy.dsh_app.links.LinksPlugin
import io.github.ccch1mneyyy.dsh_app.notify.NotifyPlugin
import io.github.ccch1mneyyy.dsh_app.phone.PhonePlugin
import io.github.ccch1mneyyy.dsh_app.remote.RemoteBackgroundService
import io.github.ccch1mneyyy.dsh_app.runtime.RuntimePlugin
import io.github.ccch1mneyyy.dsh_app.share.SharePlugin
import io.github.ccch1mneyyy.dsh_app.shortcuts.ShortcutsPlugin
import io.github.ccch1mneyyy.dsh_app.update.UpdatePlugin
import io.github.ccch1mneyyy.dsh_app.voice.VoicePlugin

/** Activity and the companion service own leases on this same process engine. */
object DshFlutterEngine {
    const val ENGINE_ID = "dsh-main"

    @Synchronized
    fun getOrCreate(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val appContext = context.applicationContext
        return FlutterEngine(appContext).also { engine ->
            engine.plugins.add(RuntimePlugin())
            engine.plugins.add(PhonePlugin())
            engine.plugins.add(NotifyPlugin())
            engine.plugins.add(FilesPlugin())
            engine.plugins.add(LinksPlugin())
            engine.plugins.add(UpdatePlugin())
            engine.plugins.add(VoicePlugin())
            engine.plugins.add(SharePlugin())
            engine.plugins.add(ShortcutsPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.diagnostics.DiagnosticsPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.media.MediaPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.media.MediaVideoPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.icons.LauncherIconPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.theme.DynamicColorPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.performance.PerformancePlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.islands.IslandsPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.nativemedia.NativeMediaPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.nativefiles.NativeFilesPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.web.WebFilesPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.launch.LaunchPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.launch.LaunchClipPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.icons.PictureShortcutPlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.companion.CompanionVoicePlugin())
            engine.plugins.add(io.github.ccch1mneyyy.dsh_app.speech.SpeechPlugin())
            // A disconnect can arrive after MainActivity has detached from this cached engine.
            MethodChannel(
                engine.dartExecutor.binaryMessenger, "io.github.ccch1mneyyy.dsh_app/remote_background",
            ).setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRemoteActive" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("bad_args", "Expected a boolean", null)
                        } else {
                            RemoteBackgroundService.setRemoteActive(appContext, enabled)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            cache.put(ENGINE_ID, engine)
        }
    }

}
