#!/system/bin/sh
echo "=== Exporting disable_3d_buildings results ==="

# Define paths
TASK_DIR="/data/local/tmp/disable_3d_buildings"
RESULT_JSON="$TASK_DIR/task_result.json"
FINAL_SCREENSHOT="$TASK_DIR/final_screenshot.png"
UI_DUMP="$TASK_DIR/ui_dump.xml"
PREFS_DUMP="$TASK_DIR/prefs_dump.txt"

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_DIR/start_time.txt" 2>/dev/null || echo "0")

# Capture Final Screenshot
screencap -p "$FINAL_SCREENSHOT"
chmod 644 "$FINAL_SCREENSHOT"

# Capture UI Hierarchy (backup verification signal)
uiautomator dump "$UI_DUMP" > /dev/null 2>&1
chmod 644 "$UI_DUMP"

# Check if App is Running
if dumpsys window windows | grep -q "com.sygic.aura"; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Attempt to read Shared Preferences (Ground Truth)
# This requires 'run-as' capability which might be available on debug builds/emulators
echo "Attempting to read shared preferences..." > "$PREFS_DUMP"
run-as com.sygic.aura sh -c "cat /data/data/com.sygic.aura/shared_prefs/*.xml" >> "$PREFS_DUMP" 2>/dev/null
# If run-as fails (permission denied), we rely on VLM.
# We also try grep directly if root is available (emulator often has root)
if [ ! -s "$PREFS_DUMP" ]; then
    cat /data/data/com.sygic.aura/shared_prefs/*.xml >> "$PREFS_DUMP" 2>/dev/null
fi
chmod 644 "$PREFS_DUMP"

# Search for relevant keys in prefs
BUILDINGS_PREF_FOUND="false"
if grep -iE "building|landmark|3d" "$PREFS_DUMP"; then
    BUILDINGS_PREF_FOUND="true"
fi

# Create JSON Result
cat > "$RESULT_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "app_was_running": $APP_RUNNING,
  "screenshot_path": "$FINAL_SCREENSHOT",
  "ui_dump_path": "$UI_DUMP",
  "prefs_dump_path": "$PREFS_DUMP",
  "prefs_data_found": $BUILDINGS_PREF_FOUND
}
EOF
chmod 644 "$RESULT_JSON"

echo "Export complete. Result saved to $RESULT_JSON"