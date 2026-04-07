#!/system/bin/sh
echo "=== Exporting set_shortest_route results ==="

PACKAGE="com.sygic.aura"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Check if App is running
if pgrep -f "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 3. Snapshot final preferences for comparison
echo "Snapshotting final preferences..."
su -c "cp -r /data/data/$PACKAGE/shared_prefs /data/local/tmp/task_snapshots/final_prefs"
su -c "chmod -R 777 /data/local/tmp/task_snapshots"

# 4. Compare Preferences (Diff) to detect changes
# We look for files that changed and contain "route" or "computing"
echo "Analyzing preference changes..."
PREFS_CHANGED="false"
CHANGED_KEYS=""

# Simple diff simulation using grep on the copied files
# specific logic: finding files in final_prefs that differ from initial_prefs
for file in $(ls /data/local/tmp/task_snapshots/final_prefs/*.xml 2>/dev/null); do
    filename=$(basename "$file")
    initial_file="/data/local/tmp/task_snapshots/initial_prefs/$filename"
    
    if [ -f "$initial_file" ]; then
        # If file content differs
        if [ "$(cat "$file")" != "$(cat "$initial_file")" ]; then
            # Check if relevant keywords are involved
            if grep -qiE "route|computing|shortest|navigation" "$file"; then
                PREFS_CHANGED="true"
                CHANGED_KEYS="$CHANGED_KEYS $filename"
            fi
        fi
    fi
done

# 5. Create Result JSON
# We write to a temp file then move to ensure atomicity
TEMP_JSON="/sdcard/task_result.tmp.json"
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "prefs_changed": $PREFS_CHANGED,
    "changed_pref_files": "$CHANGED_KEYS",
    "screenshot_path": "/sdcard/task_final.png",
    "initial_screenshot_path": "/sdcard/task_initial.png"
}
EOF

mv "$TEMP_JSON" /sdcard/task_result.json

echo "Export complete. Result at /sdcard/task_result.json"
cat /sdcard/task_result.json