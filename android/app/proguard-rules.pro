# App-specific release shrinker rules.

# SurfaceViewMapFactory sets MapLibre's draw mode through this field.
-keepclassmembers class org.maplibre.maplibregl.MapLibreMapBuilder {
    private org.maplibre.android.maps.MapLibreMapOptions options;
}
