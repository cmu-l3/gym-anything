#!/system/bin/sh
# export_result.sh for view_approach_plate@1
# Runs on Android device

echo "=== Exporting view_approach_plate task results ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final screenshot
screencap -p /sdcard/task_final_state.png 2>/dev/null || true
echo "Final screenshot saved"

# 2. Check for downloaded plate files
# We look for files created/modified AFTER task start
echo "Checking for new plate files..."

FOUND_FILES="false"
FILE_COUNT=0
NEWEST_FILE_TIME=0

# Helper function to check files in a directory
check_dir() {
    local DIR="$1"
    if [ -d "$DIR" ]; then
        # Find files with "plate" in name, newer than start time
        # Android find might not support -newer with a file, so we compare timestamps manually or rely on find if available
        # Simplified approach: List files with stats
        
        # Look for typical Avare plate files (often zips or dbs)
        local FILES=$(find "$DIR" -name "*plate*" -o -name "*Plate*" -o -name "*SanFrancisco*" 2>/dev/null)
        
        for f in $FILES; do
             # Get modification time
             local MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
             if [ "$MTIME" -gt "$TASK_START" ]; then
                 FOUND_FILES="true"
                 FILE_COUNT=$((FILE_COUNT + 1))
                 if [ "$MTIME" -gt "$NEWEST_FILE_TIME" ]; then
                     NEWEST_FILE_TIME=$MTIME
                 fi
             fi
        done
    fi
}

check_dir "/sdcard/Android/data/com.ds.avare/files"
check_dir "/data/data/com.ds.avare/files"

# 3. Check if app is running
APP_RUNNING="false"
if dumpsys activity activities | grep -q "com.ds.avare"; then
    APP_RUNNING="true"
fi

# 4. Create JSON result
# Using a temporary file approach
RESULT_JSON="/sdcard/task_result.json"

echo "{" > "$RESULT_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULT_JSON"
echo "  \"task_end\": $TASK_END," >> "$RESULT_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$RESULT_JSON"
echo "  \"plate_files_downloaded\": $FOUND_FILES," >> "$RESULT_JSON"
echo "  \"new_file_count\": $FILE_COUNT," >> "$RESULT_JSON"
echo "  \"last_file_mtime\": $NEWEST_FILE_TIME," >> "$RESULT_JSON"
echo "  \"final_screenshot_path\": \"/sdcard/task_final_state.png\"" >> "$RESULT_JSON"
echo "}" >> "$RESULT_JSON"

echo "Result JSON created at $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="