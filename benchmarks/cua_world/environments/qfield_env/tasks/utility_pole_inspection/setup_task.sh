#!/system/bin/sh
# Setup script for utility_pole_inspection task.

echo "=== Setting up utility_pole_inspection task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/utility_pole_inspection.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/utility_pole_inspection.gpkg"

am force-stop $PACKAGE
sleep 2

echo "Creating writable copy of utility_pole_inspection GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with utility_pole_inspection.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/utility_pole_inspection.gpkg" \
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
echo "=== utility_pole_inspection task setup complete ==="
echo "Agent must: review pole attributes -> apply compound replacement criteria -> set replacement_flag=SCHEDULE -> add work_order_notes -> save"
