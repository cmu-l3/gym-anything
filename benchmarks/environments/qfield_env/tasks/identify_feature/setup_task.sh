#!/system/bin/sh
# Setup script for identify_feature task.
# Opens QField with the world_survey.gpkg project showing the world map.

echo "=== Setting up identify_feature task ==="

PACKAGE="ch.opengis.qfield"
GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"

# Ensure GeoPackage is in place
if [ ! -f "$GPKG" ]; then
    echo "GeoPackage missing, copying..."
    mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
    cp /sdcard/QFieldData/world_survey.gpkg "$GPKG"
    chmod 644 "$GPKG"
fi

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

echo "=== identify_feature task setup complete ==="
echo "QField has world_survey.gpkg open showing world capitals as markers."
echo "Agent should: scroll/navigate map to Japan region -> tap Tokyo marker -> view feature attributes"
