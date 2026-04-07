#!/system/bin/sh
echo "=== Exporting download_map_hawaii results ==="

PACKAGE="com.sygic.aura"
MAP_DIR="/sdcard/Android/data/com.sygic.aura/files/Maps"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final visual state
screencap -p /sdcard/task_final.png

# 2. Check for map file existence and timestamp
# We look for files created/modified AFTER task start
echo "Checking for downloaded map files..."
FOUND_MAP="false"
MAP_SIZE="0"
MAP_TIMESTAMP="0"

# Find any file containing 'hawaii' or 'us_hi' in the maps directory
# We use a loop because 'find' output might be multi-line
for f in $(find "$MAP_DIR" -name "*hawaii*" -o -name "*us_hi*" 2>/dev/null); do
    if [ -f "$f" ]; then
        MTIME=$(stat -c %Y "$f")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            FOUND_MAP="true"
            MAP_SIZE=$(stat -c %s "$f")
            MAP_TIMESTAMP=$MTIME
            echo "Found new map file: $f"
            break
        fi
    fi
done

# 3. Check if app is running
if pidof "$PACKAGE" > /dev/null; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# 4. Dump UI hierarchy (helper for debugging/verification if needed)
uiautomator dump /sdcard/ui_dump.xml > /dev/null 2>&1

# 5. Create JSON result
# Note: writing valid JSON in shell can be tricky, keep it simple
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"map_found\": $FOUND_MAP," >> /sdcard/task_result.json
echo "  \"map_size\": $MAP_SIZE," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"final_screenshot\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "=== Export complete ==="
cat /sdcard/task_result.json