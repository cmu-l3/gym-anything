#!/system/bin/sh
# Setup script for toggle_layer_visibility task.
# Opens QField with the world_survey.gpkg project and opens the layers panel.

echo "=== Setting up toggle_layer_visibility task ==="

PACKAGE="ch.opengis.qfield"
GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# Ensure GeoPackage is in place
if [ ! -f "$GPKG" ]; then
    echo "GeoPackage missing, copying..."
    mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
    cp /sdcard/QFieldData/world_survey.gpkg "$GPKG"
    chmod 644 "$GPKG"
fi

# Force stop for clean state
am force-stop $PACKAGE
sleep 2

# Press Home
input keyevent KEYCODE_HOME
sleep 1

# Launch QField with the GeoPackage file directly using VIEW intent
echo "Launching QField with world_survey.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg" \
    -t "application/geopackage+sqlite3" \
    -n "$PACKAGE/.QFieldActivity" 2>/dev/null

# Fallback: if intent fails, launch normally
sleep 3
CURRENT=$(dumpsys window | grep mCurrentFocus)
if echo "$CURRENT" | grep -q "Launcher\|NoActivity"; then
    echo "Intent failed, launching via monkey..."
    monkey -p $PACKAGE -c android.intent.category.LAUNCHER 1 2>/dev/null
    sleep 8
else
    echo "QField launched via intent"
    sleep 14
fi

# Allow time for project to fully load
sleep 3

# Open the layers panel by tapping the layers icon (top-left hamburger/layers button)
# VG ~(85,55) at 1280x720 scale -> actual resolution 1080x2400 -> (72, 183)
echo "Opening layers panel..."
input tap 72 183
sleep 3

echo "=== toggle_layer_visibility task setup complete ==="
echo "QField has world_survey.gpkg open with layers panel visible."
echo "Agent should: find field_observations in the layer list -> toggle its visibility off"
