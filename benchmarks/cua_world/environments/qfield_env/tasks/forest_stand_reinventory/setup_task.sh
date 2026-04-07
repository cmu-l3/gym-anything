#!/system/bin/sh
# Setup script for forest_stand_reinventory task.

echo "=== Setting up forest_stand_reinventory task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/forest_stand_reinventory.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/forest_stand_reinventory.gpkg"

am force-stop $PACKAGE
sleep 2

echo "Creating writable copy of forest_stand_reinventory GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with forest_stand_reinventory.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/forest_stand_reinventory.gpkg" \
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
echo "=== forest_stand_reinventory task setup complete ==="
echo "Agent must: identify stands with last_inventory <= 2019 -> set reinventory_status=OVERDUE -> add field_notes + priority_rank -> add tree_measurements records -> save"
