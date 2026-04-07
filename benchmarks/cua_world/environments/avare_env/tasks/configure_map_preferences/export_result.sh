#!/system/bin/sh
echo "=== Exporting configure_map_preferences results ==="

# Define paths
PACKAGE="com.ds.avare"
PREFS_FILE="/data/data/$PACKAGE/shared_prefs/com.ds.avare_preferences.xml"
TEMP_DIR="/sdcard/task_tmp"

# 1. Record task end time
date +%s > "$TEMP_DIR/task_end_time.txt"

# 2. Take final screenshot
screencap -p "$TEMP_DIR/task_final.png"

# 3. Capture final preferences file
# We copy it to the temp dir which is accessible for copy_from_env
echo "Capturing final preferences..."
if su 0 ls "$PREFS_FILE" > /dev/null 2>&1; then
    su 0 cat "$PREFS_FILE" > "$TEMP_DIR/final_prefs.xml"
    su 0 stat -c %Y "$PREFS_FILE" > "$TEMP_DIR/final_prefs_mtime.txt"
else
    echo "ERROR: Final preferences file not found!"
    echo "MISSING" > "$TEMP_DIR/final_prefs.xml"
fi

# 4. Check if app is in foreground (for 'Returned to Map' verification)
# We dump the window hierarchy or check focus
dumpsys window | grep -i "mCurrentFocus" > "$TEMP_DIR/final_focus.txt"

# 5. Create a JSON summary for the verifier
# Note: Complex parsing happens in Python verifier, we just export raw data
cat <<EOF > "$TEMP_DIR/task_result.json"
{
  "task_completed_at": "$(date)",
  "prefs_file_exists": $(if [ -s "$TEMP_DIR/final_prefs.xml" ]; then echo "true"; else echo "false"; fi),
  "screenshot_path": "$TEMP_DIR/task_final.png"
}
EOF

# Set permissions so host can pull files
chmod -R 777 "$TEMP_DIR"

echo "=== Export complete ==="