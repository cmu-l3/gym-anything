#!/bin/bash
echo "=== Exporting SAR Task Results ==="

PACKAGE="ch.opengis.qfield"
GPKG_PATH="/sdcard/Android/data/$PACKAGE/files/Imported Datasets/world_survey.gpkg"
LOCAL_EXPORT_GPKG="/tmp/exported_world_survey.gpkg"

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
echo "Capturing final screenshot..."
adb shell screencap -p /sdcard/task_final.png
adb pull /sdcard/task_final.png /tmp/task_final.png

# 3. Export GeoPackage for Verification
echo "Pulling GeoPackage from device..."
adb pull "$GPKG_PATH" "$LOCAL_EXPORT_GPKG"

GPKG_EXISTS="false"
GPKG_SIZE="0"
if [ -f "$LOCAL_EXPORT_GPKG" ]; then
    GPKG_EXISTS="true"
    GPKG_SIZE=$(stat -c %s "$LOCAL_EXPORT_GPKG")
fi

# 4. Check if App is Running
APP_RUNNING="false"
if adb shell pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gpkg_exists": $GPKG_EXISTS,
    "gpkg_size": $GPKG_SIZE,
    "gpkg_path": "$LOCAL_EXPORT_GPKG",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json