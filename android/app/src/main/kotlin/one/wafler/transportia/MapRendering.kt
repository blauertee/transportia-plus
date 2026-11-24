package one.wafler.transportia

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.maplibre.maplibregl.SurfaceViewMapFactory

/**
 * How maps are drawn on this phone, chosen from what its GPU offers or set
 * by hand in the advanced settings (`lib/services/map_rendering_service.dart`
 * is the other end).
 *
 * Three choices make up a profile:
 * - `renderer`: Flutter's own renderer, `impeller` or `skia`. The engine
 *   reads it once per process, so it is decided here, before Flutter starts,
 *   and a change applies from the next start.
 * - `composition`: how the map's native view reaches the screen. `texture`
 *   copies it into Flutter's picture; `hybrid` lets Android draw it as a view
 *   of its own.
 * - `surface`: whether MapLibre draws into a `textureView` or a
 *   `surfaceView`.
 *
 * The choice is kept in Android's own preferences rather than Flutter's,
 * because the renderer has to be known before any Dart code runs.
 */
class MapRendering private constructor(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "transportia/map_rendering"
        /** Left out of backups (`res/xml/backup_rules.xml`): the choice fits one phone. */
        private const val PREFS = "map_rendering"

        private const val RENDERER = "renderer"
        private const val COMPOSITION = "composition"
        private const val SURFACE = "surface"
        private val KEYS = listOf(RENDERER, COMPOSITION, SURFACE)

        /**
         * The Dart version an override was set under, which moves with every
         * Flutter release; the Dart side drops an override from an older one.
         */
        private const val DART_VERSION = "dartVersion"

        private const val SKIA = "skia"

        /** What every phone with a working Vulkan driver gets. */
        private val STANDARD = mapOf(
            RENDERER to "impeller",
            COMPOSITION to "texture",
            SURFACE to "textureView",
        )

        /**
         * What phones get where Impeller draws with OpenGL ES. On some older
         * drivers the map's texture then stays blank; hybrid composition
         * draws the map outside Flutter's picture. Skia draws it too, but
         * Flutter is phasing Skia out on Android.
         */
        private val COMPATIBLE = mapOf(
            RENDERER to "impeller",
            COMPOSITION to "hybrid",
            SURFACE to "textureView",
        )

        /**
         * `VK_API_VERSION_1_1` as Android encodes it: the lowest Vulkan that
         * Impeller's Vulkan backend runs on.
         */
        private const val VULKAN_1_1 = 0x00401000

        /**
         * Below this, the engine runs Skia whatever it is asked, and the map
         * draws without help (`kMinimumAndroidApiLevelForImpeller` in the
         * engine).
         */
        private const val IMPELLER_MIN_SDK = Build.VERSION_CODES.Q

        /** Platform view type of [SurfaceViewMapFactory]. */
        private const val SURFACE_VIEW_MAP_TYPE = "transportia/maplibre_surface_view"

        /**
         * The renderer this process's engine was started with. The engine
         * takes its arguments once per process, so only the first call to
         * [shellArgs] counts.
         */
        private var rendererInUse: String? = null

        /** Engine arguments that put the chosen renderer in place. */
        fun shellArgs(context: Context): List<String> {
            val renderer = rendererInUse ?: effective(context).getValue(RENDERER)
            rendererInUse = renderer
            return if (renderer == SKIA) listOf("--enable-impeller=false") else emptyList()
        }

        fun register(engine: FlutterEngine, activity: MainActivity) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(MapRendering(activity.applicationContext))
            engine.platformViewsController.registry.registerViewFactory(
                SURFACE_VIEW_MAP_TYPE,
                SurfaceViewMapFactory(engine.dartExecutor.binaryMessenger) {
                    activity.lifecycle
                },
            )
        }

        /**
         * Whether Impeller would run here without Vulkan, on OpenGL ES: the
         * one case the compatible profile is for. Everything else keeps the
         * engine's and the plugin's own defaults, whatever they become.
         */
        private fun impellerOnOpenGl(context: Context): Boolean =
            Build.VERSION.SDK_INT >= IMPELLER_MIN_SDK &&
                !context.packageManager.hasSystemFeature(
                    PackageManager.FEATURE_VULKAN_HARDWARE_VERSION,
                    VULKAN_1_1,
                )

        private fun detected(context: Context): Map<String, String> =
            if (impellerOnOpenGl(context)) COMPATIBLE else STANDARD

        /** The profile set by hand, or null while the app chooses. */
        private fun override(context: Context): Map<String, String>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val values = KEYS.associateWith { prefs.getString(it, null) }
            if (values.values.any { it == null }) return null
            return values.mapValues { it.value!! }
        }

        private fun effective(context: Context): Map<String, String> =
            override(context) ?: detected(context)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(
                mapOf(
                    "detected" to detected(context),
                    "override" to override(context),
                    "rendererInUse" to (rendererInUse ?: STANDARD.getValue(RENDERER)),
                    "overrideDartVersion" to context
                        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        .getString(DART_VERSION, null),
                ),
            )
            "setOverride" -> {
                val profile = call.arguments as Map<*, *>?
                val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                for (key in KEYS + DART_VERSION) {
                    val value = profile?.get(key) as String?
                    if (value == null) editor.remove(key) else editor.putString(key, value)
                }
                editor.apply()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
