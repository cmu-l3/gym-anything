#!/system/bin/sh
# Setup script for crop_pest_scouting task.

echo "=== Setting up crop_pest_scouting task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/crop_pest_scouting.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/crop_pest_scouting.gpkg"

am force-stop $PACKAGE
sleep 2

echo "Creating writable copy of crop_pest_scouting GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with crop_pest_scouting.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/crop_pest_scouting.gpkg" \
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

sleep 3
echo "=== crop_pest_scouting task setup complete ==="
echo "Agent must: check pest counts against IPM thresholds -> set treatment_recommendation=TREAT where exceeded -> add action_notes -> add recheck_date -> save"
