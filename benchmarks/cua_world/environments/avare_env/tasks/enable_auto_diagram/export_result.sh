#!/system/bin/sh
echo "=== Exporting Task Results ==="

# 1. Define paths
PACKAGE="com.ds.avare"
PREFS_SOURCE="/data/data/$PACKAGE/shared_prefs/${PACKAGE}_preferences.xml"
EXPORT_DIR="/sdcard"
RESULT_JSON="$EXPORT_DIR/task_result.json"

# 2. Capture final state screenshot
screencap -p "$EXPORT_DIR/task_final.png"

# 3. Check timestamps
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Check if preferences file was modified
FILE_MODIFIED="false"
FILE_SIZE="0"

# We need to copy the protected prefs file to sdcard so the verifier (running on host) can read it
# Using su to access /data/data
if su 0 ls "$PREFS_SOURCE" >/dev/null 2>&1; then
    echo "Preferences file found."
    
    # Check modification time
    # Android ls -l format: -rw-rw---- 1 u0_a156 u0_a156 3125 2023-10-27 10:00 filename
    # We'll rely on python verifier for precise diffs, but capture existence here
    
    # Copy file for verifier inspection
    su 0 cp "$PREFS_SOURCE" "$EXPORT_DIR/final_preferences.xml"
    chmod 666 "$EXPORT_DIR/final_preferences.xml"
    
    FILE_SIZE=$(stat -c %s "$EXPORT_DIR/final_preferences.xml" 2>/dev/null || echo "0")
    
    # Simple check if file is newer than start (rough check)
    FILE_MTIME=$(stat -c %Y "$EXPORT_DIR/final_preferences.xml" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
else
    echo "Preferences file NOT found or not accessible."
fi

# 5. Check if app is in foreground (to verify "Return to Map")
# Get current focus
CURRENT_FOCUS=$(dumpsys window | grep mCurrentFocus)
IS_MAP_VIEW="false"
# Avare's main map activity is typically MainActivity or MapActivity
if echo "$CURRENT_FOCUS" | grep -q "$PACKAGE"; then
    APP_OPEN="true"
    # Heuristic: If we are not in PreferencesActivity, we might be on Map
    if ! echo "$CURRENT_FOCUS" | grep -q "Preferences"; then
        IS_MAP_VIEW="true"
    fi
else
    APP_OPEN="false"
fi

# 6. Write result JSON
echo "{
    \"task_start\": $TASK_START,
    \"task_end\": $TASK_END,
    \"prefs_file_exported\": $([ -f "$EXPORT_DIR/final_preferences.xml" ] && echo "true" || echo "false"),
    \"prefs_file_modified\": $FILE_MODIFIED,
    \"app_running\": $APP_OPEN,
    \"returned_to_map\": $IS_MAP_VIEW
}" > "$RESULT_JSON"

chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="
cat "$RESULT_JSON"