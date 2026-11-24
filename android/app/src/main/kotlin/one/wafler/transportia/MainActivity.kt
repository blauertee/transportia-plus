package one.wafler.transportia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterActivity() {
    override fun getFlutterShellArgs(): FlutterShellArgs =
        FlutterShellArgs(
            super.getFlutterShellArgs().toArray().toList() + MapRendering.shellArgs(this),
        )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        CalendarBridge.register(flutterEngine, this)
        MapRendering.register(flutterEngine, this)
    }
}
