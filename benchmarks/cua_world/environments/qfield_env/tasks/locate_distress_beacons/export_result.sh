#!/system/bin/sh
echo "=== Exporting locate_distress_beacons result ==="

PACKAGE="ch.opengis.qfield"
WORKING_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
EXPORT_GPKG="/sdcard/task_result.gpkg"

# 1. Force stop QField to ensure SQLite WAL file is flushed/checkpointed
am force-stop $PACKAGE
sleep 3

# 2. Copy the modified GeoPackage to a staging location for the verifier
# This ensures we get the latest state
if [ -f "$WORKING_GPKG" ]; then
    cp "$WORKING_GPKG" "$EXPORT_GPKG"
    chmod 666 "$EXPORT_GPKG"
    echo "Exported GeoPackage to $EXPORT_GPKG"
    ls -l "$EXPORT_GPKG"
else
    echo "ERROR: Working GeoPackage not found!"
fi

# 3. Check if app was running (retrospective check hard on Android, assuming setup worked)
# We rely on the file modification time vs start marker

# 4. Take final screenshot (framework handles this usually, but we do it explicitly just in case)
screencap -p /sdcard/task_final.png

echo "=== Export complete ==="