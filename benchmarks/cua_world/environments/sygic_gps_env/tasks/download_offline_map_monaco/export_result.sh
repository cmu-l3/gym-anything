#!/system/bin/sh
echo "=== Exporting download_offline_map_monaco results ==="

# 1. Capture Final Screenshot
screencap -p /sdcard/task_final.png

# 2. Gather Task Execution Data
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
MAPS_DIR="/sdcard/Android/data/com.sygic.aura/files/Maps"

# 3. Check for New Map Files (Monaco specific)
# We look for files containing 'mco' (Monaco ISO code often used) or 'monaco'
# created/modified after TASK_START
MONACO_FOUND="false"
NEW_FILE_DETECTED="false"
MAP_FILE_PATH=""
MAP_FILE_SIZE="0"

# Find files matching monaco patterns
# Note: Android find might be limited, using simple ls grep approach first
echo "Searching for Monaco map files..."
FOUND_FILES=$(find "$MAPS_DIR" -type f -name "*mco*" -o -name "*monaco*" 2>/dev/null)

if [ -n "$FOUND_FILES" ]; then
    for f in $FOUND_FILES; do
        # Check timestamp
        # Android stat format can vary. using -c %Y
        F_TIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        
        if [ "$F_TIME" -ge "$TASK_START" ]; then
            MONACO_FOUND="true"
            NEW_FILE_DETECTED="true"
            MAP_FILE_PATH="$f"
            MAP_FILE_SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
            echo "Found new Monaco map: $f (Size: $MAP_FILE_SIZE)"
            break
        elif [ "$F_TIME" -gt 0 ]; then
             # File exists but is old? Maybe user re-downloaded?
             # If size > 0, we might accept it if we can prove it was updated.
             # But for now, strictly enforce timestamp to prevent pre-downloaded gaming.
             echo "Found old Monaco map: $f (Time: $F_TIME vs Start: $TASK_START)"
        fi
    done
fi

# 4. Check Total Size Change (Fallback Verification)
INITIAL_SIZE_LINE=$(cat /sdcard/initial_maps_size.txt 2>/dev/null || echo "0")
INITIAL_SIZE=$(echo "$INITIAL_SIZE_LINE" | awk '{print $1}')
CURRENT_SIZE_LINE=$(du -s "$MAPS_DIR" 2>/dev/null || echo "0")
CURRENT_SIZE=$(echo "$CURRENT_SIZE_LINE" | awk '{print $1}')

SIZE_INCREASED="false"
if [ "$CURRENT_SIZE" -gt "$INITIAL_SIZE" ]; then
    SIZE_INCREASED="true"
fi

# 5. Check App State
APP_RUNNING="false"
if pidof com.sygic.aura > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create JSON Result
# Using manual JSON construction because jq might not be on Android
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"monaco_map_found\": $MONACO_FOUND," >> /sdcard/task_result.json
echo "  \"new_file_detected\": $NEW_FILE_DETECTED," >> /sdcard/task_result.json
echo "  \"map_file_path\": \"$MAP_FILE_PATH\"," >> /sdcard/task_result.json
echo "  \"map_file_size_bytes\": $MAP_FILE_SIZE," >> /sdcard/task_result.json
echo "  \"total_maps_size_increased\": $SIZE_INCREASED," >> /sdcard/task_result.json
echo "  \"app_was_running\": $APP_RUNNING," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON created at /sdcard/task_result.json:"
cat /sdcard/task_result.json
echo "=== Export Complete ==="