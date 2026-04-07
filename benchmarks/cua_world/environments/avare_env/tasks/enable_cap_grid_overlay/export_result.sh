#!/system/bin/sh
# Export script for enable_cap_grid_overlay task

echo "=== Exporting Task Results ==="

PACKAGE="com.ds.avare"
PREFS_PATH="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
EXPORT_DIR="/sdcard"

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Preferences File
# We copy it to /sdcard so the host verifier can pull it easily via copy_from_env
# (The internal data path is often restricted)
if [ -f "$PREFS_PATH" ]; then
    cp "$PREFS_PATH" "$EXPORT_DIR/final_preferences.xml"
    chmod 666 "$EXPORT_DIR/final_preferences.xml"
    PREFS_EXISTS="true"
    
    # Get file modification time (using ls -l as simple stat substitute on limited android shell)
    # This is a rough check; verification logic on host is better
    PREFS_MTIME=$(date -r "$PREFS_PATH" +%s 2>/dev/null || echo "0")
else
    PREFS_EXISTS="false"
    PREFS_MTIME="0"
fi

# 3. Capture Final Screenshot
screencap -p "$EXPORT_DIR/final_screenshot.png"
SCREENSHOT_EXISTS=$([ -f "$EXPORT_DIR/final_screenshot.png" ] && echo "true" || echo "false")

# 4. Check if App is Running
APP_RUNNING=$(pidof $PACKAGE > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# Android shell json creation
cat > "$EXPORT_DIR/task_result.json" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "prefs_exists": $PREFS_EXISTS,
  "prefs_mtime": $PREFS_MTIME,
  "app_running": $APP_RUNNING,
  "screenshot_path": "$EXPORT_DIR/final_screenshot.png",
  "prefs_path": "$EXPORT_DIR/final_preferences.xml"
}
EOF

chmod 666 "$EXPORT_DIR/task_result.json"
echo "Result exported to $EXPORT_DIR/task_result.json"
cat "$EXPORT_DIR/task_result.json"