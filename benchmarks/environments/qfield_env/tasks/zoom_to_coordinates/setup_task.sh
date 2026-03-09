#!/system/bin/sh
# Setup script for zoom_to_coordinates task.
# Opens QField with a fresh copy of world_survey.gpkg (no cached viewport)
# so the map opens at a clean default world extent.

echo "=== Setting up zoom_to_coordinates task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/world_survey.gpkg"
GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# Always copy a fresh GPKG to clear any saved viewport/camera state
echo "Copying fresh GeoPackage (clears saved viewport)..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG"
chmod 644 "$GPKG"

# Force stop
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch QField with the GeoPackage
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

sleep 3
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent failed, launching via monkey..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
else
    sleep 14
fi

sleep 5

echo "=== zoom_to_coordinates task setup complete ==="
echo "QField has world_survey.gpkg open showing a world map."
echo "Agent should: navigate to coordinates lat=-33.8688, lon=151.2093 (Sydney, Australia)"
