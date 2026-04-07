#!/system/bin/sh
# Export script for configure_distance_rings
# Runs on Android environment

echo "=== Exporting Results ==="

TASK_DIR="/sdcard/tasks/configure_distance_rings"
PREFS_SOURCE="/data/data/com.ds.avare/shared_prefs/com.ds.avare_preferences.xml"
PREFS_DEST="$TASK_DIR/prefs_dump.xml"
RESULT_JSON="$TASK_DIR/task_result.json"

# 1. Capture Final Screenshot
screencap -p "$TASK_DIR/final_screenshot.png"

# 2. Export Preferences File
# Needs root access to read /data/data. Assuming script runs as root or capable user.
# If strict permissions prevent direct cp, try run-as (if debuggable) or cat.
# We'll try cat first.
if [ -f "$PREFS_SOURCE" ]; then
    cat "$PREFS_SOURCE" > "$PREFS_DEST"
    chmod 666 "$PREFS_DEST"
    PREFS_EXISTS="true"
    
    # Get modification time if possible (Android ls -l output)
    # Format: -rw-rw---- 1 u0_a136 u0_a136 1234 2023-10-25 12:00 ...
    # We'll just grab the raw ls output for the verifier to parse if needed, 
    # or rely on the fact that if the value is 5/10, it was likely changed by the agent (defaults are usually different).
    PREFS_STAT=$(ls -l "$PREFS_SOURCE")
else
    echo "Preferences file not found at $PREFS_SOURCE"
    PREFS_EXISTS="false"
    PREFS_STAT=""
fi

# 3. Get Task Start Time
if [ -f "$TASK_DIR/start_time.txt" ]; then
    START_TIME=$(cat "$TASK_DIR/start_time.txt")
else
    START_TIME="0"
fi
END_TIME=$(date +%s)

# 4. Create JSON Result
# We construct JSON manually using echo/cat
cat > "$RESULT_JSON" <<EOF
{
  "task_start_time": $START_TIME,
  "task_end_time": $END_TIME,
  "prefs_file_exists": $PREFS_EXISTS,
  "prefs_file_path": "$PREFS_DEST",
  "prefs_file_stat": "$PREFS_STAT",
  "final_screenshot_path": "$TASK_DIR/final_screenshot.png"
}
EOF

# Ensure permissions for the agent to pull these files
chmod -R 777 "$TASK_DIR"

echo "=== Export Complete ==="
cat "$RESULT_JSON"