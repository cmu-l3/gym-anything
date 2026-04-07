#!/system/bin/sh
# Setup script for utility_line_vegetation_clearance_audit task.

echo "=== Setting up utility_line_vegetation_clearance_audit task ==="

PACKAGE="ch.opengis.qfield"
GPKG_SRC="/sdcard/QFieldData/utility_line_vegetation_clearance_audit.gpkg"
GPKG_TASK="/sdcard/Android/data/ch.opengis.qfield/files/utility_line_vegetation_clearance_audit.gpkg"

am force-stop $PACKAGE
sleep 2

echo "Creating writable copy of utility_line_vegetation_clearance_audit GeoPackage..."
mkdir -p /sdcard/Android/data/ch.opengis.qfield/files
cp "$GPKG_SRC" "$GPKG_TASK"
chmod 666 "$GPKG_TASK"
echo "GeoPackage ready at $GPKG_TASK"

input keyevent KEYCODE_HOME
sleep 1

echo "Launching QField with utility_line_vegetation_clearance_audit.gpkg..."
am start -a android.intent.action.VIEW \
    -d "file:///sdcard/Android/data/ch.opengis.qfield/files/utility_line_vegetation_clearance_audit.gpkg" \
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
echo "=== utility_line_vegetation_clearance_audit task setup complete ==="
echo "QField has utility_line_vegetation_clearance_audit.gpkg open (editable)."
echo "Agent must: review vegetation_survey -> find trees failing NERC/ANSI clearance -> set clearance_status=TRIM_REQUIRED -> add trim_reason -> save"
