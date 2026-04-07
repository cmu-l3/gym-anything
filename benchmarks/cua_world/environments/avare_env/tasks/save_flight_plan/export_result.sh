#!/system/bin/sh
# Export script for save_flight_plan task
# Scans for the saved flight plan file and exports its content and metadata

echo "=== Exporting save_flight_plan results ==="

PACKAGE="com.ds.avare"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_JSON="/sdcard/task_result.json"

# 1. Take final screenshot
screencap -p /sdcard/task_final.png

# 2. Search for the plan file
# Avare might save as .json, .txt, or internal DB. We search for the name.
echo "Searching for plan file 'BayAreaTraining'..."

PLAN_PATH=""
PLAN_CONTENT=""
PLAN_MTIME="0"

# Helper to check a file
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        # Get modification time
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        
        # Check if modified after task start
        if [ "$mtime" -gt "$TASK_START" ]; then
            PLAN_PATH="$f"
            PLAN_MTIME="$mtime"
            PLAN_CONTENT=$(cat "$f")
            echo "Found valid plan file: $f"
            return 0
        fi
    fi
    return 1
}

# Search locations
# Location 1: Android/data external
find /sdcard/Android/data/$PACKAGE -name "*BayAreaTraining*" 2>/dev/null | while read f; do
    check_file "$f" && break
done

# Location 2: Legacy sdcard path
if [ -z "$PLAN_PATH" ]; then
    find /sdcard/com.ds.avare -name "*BayAreaTraining*" 2>/dev/null | while read f; do
        check_file "$f" && break
    done
fi

# Location 3: Internal data (try to cat via run-as if not root, or direct if root)
if [ -z "$PLAN_PATH" ]; then
    # Try direct find first (assuming root in emulator)
    INTERNAL_FILES=$(find /data/data/$PACKAGE -name "*BayAreaTraining*" 2>/dev/null)
    for f in $INTERNAL_FILES; do
        check_file "$f" && break
    done
fi

# 3. Check application state
APP_RUNNING="false"
if pidof $PACKAGE > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Create JSON output
# Note: constructing JSON manually in shell
echo "{" > $OUTPUT_JSON
echo "  \"task_start\": $TASK_START," >> $OUTPUT_JSON
echo "  \"plan_found\": $(if [ -n "$PLAN_PATH" ]; then echo "true"; else echo "false"; fi)," >> $OUTPUT_JSON
echo "  \"plan_path\": \"$PLAN_PATH\"," >> $OUTPUT_JSON
echo "  \"plan_mtime\": $PLAN_MTIME," >> $OUTPUT_JSON
echo "  \"app_running\": $APP_RUNNING," >> $OUTPUT_JSON
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"," >> $OUTPUT_JSON
# Escape quotes in content
SAFE_CONTENT=$(echo "$PLAN_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')
echo "  \"plan_content\": \"$SAFE_CONTENT\"" >> $OUTPUT_JSON
echo "}" >> $OUTPUT_JSON

# 5. Set permissions so host can read it
chmod 666 $OUTPUT_JSON 2>/dev/null

echo "Export complete. Result saved to $OUTPUT_JSON"
cat $OUTPUT_JSON