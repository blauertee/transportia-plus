package org.maplibre.maplibregl

import android.content.Context
import android.util.Log
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.maplibre.android.maps.MapLibreMapOptions

/**
 * Builds maps the way the maplibre_gl plugin's own `MapLibreMapFactory`
 * does, except that MapLibre draws into a SurfaceView instead of a
 * TextureView. The plugin fixes texture mode in `MapLibreMapBuilder`, and
 * some older GPU drivers fail in its TextureView renderer.
 *
 * Lives in the plugin's package because the builder, `Convert` and the
 * lifecycle provider are package-private there. Registered by
 * `one.wafler.transportia.MapRendering`; keep in step with the plugin's
 * factory when maplibre_gl is updated.
 */
class SurfaceViewMapFactory(
    private val messenger: BinaryMessenger,
    private val lifecycle: () -> Lifecycle?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as Map<String, Any?>
        val builder = MapLibreMapBuilder()
        drawToSurfaceView(builder)

        Convert.interpretMapLibreMapOptions(params["options"], builder, context)
        params["initialCameraPosition"]?.let {
            builder.setInitialCameraPosition(Convert.toCameraPosition(it))
        }
        params["dragEnabled"]?.let { builder.setDragEnabled(Convert.toBoolean(it)) }
        params["styleString"]?.let { builder.setStyleString(Convert.toString(it)) }

        return builder.build(
            viewId,
            context,
            messenger,
            MapLibreMapsPlugin.LifecycleProvider { lifecycle() },
        )
    }

    /**
     * The builder keeps its options in a private field; the release
     * shrinker keeps that field's name (`proguard-rules.pro`). Should it ever
     * be missing, the map still opens, in texture mode.
     */
    private fun drawToSurfaceView(builder: MapLibreMapBuilder) {
        try {
            val field = MapLibreMapBuilder::class.java.getDeclaredField("options")
            field.isAccessible = true
            (field.get(builder) as MapLibreMapOptions).textureMode(false)
        } catch (e: ReflectiveOperationException) {
            Log.w("SurfaceViewMapFactory", "Map stays in texture mode", e)
        }
    }
}
