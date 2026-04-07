#!/bin/bash
echo "=== Exporting task results ==="

# Define paths
ANDROID_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
LOCAL_EXPORT="/tmp/task_export.gpkg"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Pull the GeoPackage to check the data
echo "Pulling GeoPackage for verification..."
adb pull "$ANDROID_GPKG" "$LOCAL_EXPORT"

# 2. Check file modification time on Android (Anti-gaming)
# We check if the file was modified AFTER the task start time.
# stat on Android might differ, so we use ls -l or stat if available.
ANDROID_MTIME=$(adb shell "stat -c %Y '$ANDROID_GPKG'" 2>/dev/null || echo "0")
# If stat fails on android, fallback to 0 (will fail verification if strict)

FILE_MODIFIED="false"
if [ "$ANDROID_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 3. Take Final Screenshot
echo "Capturing final screenshot..."
adb exec-out screencap -p > /tmp/task_final.png

# 4. Create result JSON for the verifier
# We will verify the specific data content in the Python verifier, 
# but we export metadata here.
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified_during_task": $FILE_MODIFIED,
    "android_mtime": $ANDROID_MTIME,
    "gpkg_path": "$LOCAL_EXPORT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 644 /tmp/task_result.json
chmod 644 /tmp/task_final.png
chmod 644 "$LOCAL_EXPORT"

echo "Export complete. Result at /tmp/task_result.json"