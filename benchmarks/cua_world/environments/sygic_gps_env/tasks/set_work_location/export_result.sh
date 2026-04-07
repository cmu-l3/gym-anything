#!/system/bin/sh
# Export script for set_work_location
# Runs on Android device

echo "=== Exporting set_work_location results ==="

PACKAGE="com.sygic.aura"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# 1. Take final screenshot
screencap -p /sdcard/task_final.png

# 2. Check for Preference Modifications (Anti-gaming)
# We look for files modified AFTER task start
MODIFIED_FILES_COUNT=0
su 0 find /data/data/$PACKAGE/shared_prefs/ -type f -newermt "@$TASK_START" > /sdcard/modified_files.txt 2>/dev/null
MODIFIED_FILES_COUNT=$(cat /sdcard/modified_files.txt | wc -l)

# 3. Search for Target Data in App Data
# We look for "World Trade" or coordinates in the app's internal files
FOUND_TEXT="false"
FOUND_COORDS="false"

# Copy current prefs to sdcard for readable grep
mkdir -p /sdcard/task_export/prefs
su 0 cp -r /data/data/$PACKAGE/shared_prefs/* /sdcard/task_export/prefs/ 2>/dev/null || true
su 0 chmod -R 777 /sdcard/task_export/prefs

# Search text
if grep -ri "World Trade" /sdcard/task_export/prefs/ > /dev/null; then
    FOUND_TEXT="true"
fi

# Search coords (simple grep for lat prefix 40.7 and lon prefix -74.0)
if grep -r "40.7" /sdcard/task_export/prefs/ | grep "\-74.0" > /dev/null; then
    FOUND_COORDS="true"
fi

# 4. Create JSON Result
cat > /sdcard/task_result.json <<EOF
{
  "task_start_time": $TASK_START,
  "task_end_time": $NOW,
  "app_files_modified": $MODIFIED_FILES_COUNT,
  "data_found_text": $FOUND_TEXT,
  "data_found_coords": $FOUND_COORDS,
  "screenshot_path": "/sdcard/task_final.png"
}
EOF

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="