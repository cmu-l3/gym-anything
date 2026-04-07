#!/system/bin/sh
echo "=== Exporting deploy_coastal_flood_sensors result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# Paths
# QField might edit the one in "Imported Datasets" or the root one depending on how it opened.
# We check the most recently modified one.
GPKG_1="/sdcard/Android/data/ch.opengis.qfield/files/world_survey.gpkg"
GPKG_2="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"

# Find which file was modified
TARGET_GPKG=""
if [ -f "$GPKG_2" ]; then
    M2=$(stat -c %Y "$GPKG_2")
    if [ "$M2" -gt "$TASK_START" ]; then
        TARGET_GPKG="$GPKG_2"
    fi
fi

if [ -z "$TARGET_GPKG" ] && [ -f "$GPKG_1" ]; then
    M1=$(stat -c %Y "$GPKG_1")
    if [ "$M1" -gt "$TASK_START" ]; then
        TARGET_GPKG="$GPKG_1"
    fi
fi

# Fallback to GPKG_2 if neither seems modified (agent might have done nothing)
if [ -z "$TARGET_GPKG" ]; then
    TARGET_GPKG="$GPKG_2"
fi

echo "Using GeoPackage: $TARGET_GPKG"

# Prepare output for verifier
# We copy the GPKG to a standard location that copy_from_env can access cleanly
OUTPUT_GPKG="/sdcard/task_output.gpkg"
cp "$TARGET_GPKG" "$OUTPUT_GPKG"
chmod 666 "$OUTPUT_GPKG"

# Check if QField is running
APP_RUNNING=$(pidof ch.opengis.qfield > /dev/null && echo "true" || echo "false")

# Take final screenshot
screencap -p /sdcard/task_final.png

# Create JSON result
# Note: detailed verification happens in Python, this is just metadata
cat > /sdcard/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "gpkg_path": "$OUTPUT_GPKG",
    "source_gpkg_used": "$TARGET_GPKG"
}
EOF

echo "Export complete. Result at /sdcard/task_result.json"