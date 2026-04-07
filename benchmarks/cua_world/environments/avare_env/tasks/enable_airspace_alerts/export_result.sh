#!/system/bin/sh
# Export script for enable_airspace_alerts task
# Runs on Android device

echo "=== Exporting results ==="

PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
EXPORT_DIR="/sdcard/task_results"
mkdir -p "$EXPORT_DIR"

# 1. Capture final screenshot
screencap -p "$EXPORT_DIR/final_screenshot.png"

# 2. Copy preferences file for verification
# We copy to sdcard because the verifier (via adb/docker) might not have direct root access to /data/data
if [ -f "$PREFS_FILE" ]; then
    cp "$PREFS_FILE" "$EXPORT_DIR/preferences.xml"
    chmod 666 "$EXPORT_DIR/preferences.xml"
    
    # Get file stats for anti-gaming check
    FILE_SIZE=$(ls -l "$PREFS_FILE" | awk '{print $4}')
    FILE_DATE=$(date -r "$PREFS_FILE" +%s)
else
    echo "Preferences file not found!"
    FILE_SIZE=0
    FILE_DATE=0
fi

# 3. Get Task Start Time
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 4. Create JSON result
# Note: Android shell usually has limited JSON tools, so we construct manually
cat > "$EXPORT_DIR/result.json" << EOF
{
    "task_start_time": $START_TIME,
    "prefs_mod_time": $FILE_DATE,
    "prefs_file_exists": $([ -f "$EXPORT_DIR/preferences.xml" ] && echo "true" || echo "false"),
    "screenshot_path": "$EXPORT_DIR/final_screenshot.png"
}
EOF

echo "Result exported to $EXPORT_DIR/result.json"
cat "$EXPORT_DIR/result.json"