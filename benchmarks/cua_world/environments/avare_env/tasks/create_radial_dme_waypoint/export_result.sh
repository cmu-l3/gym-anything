#!/system/bin/sh
echo "=== Exporting create_radial_dme_waypoint results ==="

PACKAGE="com.ds.avare"
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Capture final screenshot
screencap -p /sdcard/task_final_state.png

# Attempt to locate and read the flight plan file
# Avare typically saves the current plan to a specific file
PLAN_CONTENT=""
PLAN_FILE_FOUND="false"
PLAN_PATH=""

# List of potential locations for the plan file
POTENTIAL_PATHS=(
    "/data/data/com.ds.avare/files/plans/Current.plan"
    "/sdcard/com.ds.avare/plans/Current.plan"
    "/data/user/0/com.ds.avare/files/plans/Current.plan"
)

for path in "${POTENTIAL_PATHS[@]}"; do
    if [ -f "$path" ]; then
        # Check if modified during task
        MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            echo "Found active plan file at $path"
            PLAN_PATH="$path"
            PLAN_FILE_FOUND="true"
            # Read content (it's text/JSON)
            PLAN_CONTENT=$(cat "$path")
            break
        fi
    fi
done

# If not found by timestamp, look for any Current.plan
if [ "$PLAN_FILE_FOUND" = "false" ]; then
    for path in "${POTENTIAL_PATHS[@]}"; do
        if [ -f "$path" ]; then
            echo "Found plan file (timestamp uncertain) at $path"
            PLAN_PATH="$path"
            PLAN_FILE_FOUND="true"
            PLAN_CONTENT=$(cat "$path")
            break
        fi
    done
fi

# Check if app is running
APP_RUNNING=$(pidof $PACKAGE > /dev/null && echo "true" || echo "false")

# Create JSON result
# We use a temp file to avoid issues with special chars in PLAN_CONTENT
TEMP_JSON="/sdcard/task_result_temp.json"
RESULT_JSON="/sdcard/task_result.json"

# Escape quotes in plan content for JSON inclusion
ESCAPED_PLAN=$(echo "$PLAN_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')

echo "{" > $TEMP_JSON
echo "  \"task_start\": $TASK_START," >> $TEMP_JSON
echo "  \"task_end\": $TASK_END," >> $TEMP_JSON
echo "  \"app_running\": $APP_RUNNING," >> $TEMP_JSON
echo "  \"plan_found\": $PLAN_FILE_FOUND," >> $TEMP_JSON
echo "  \"plan_path\": \"$PLAN_PATH\"," >> $TEMP_JSON
echo "  \"plan_content\": \"$ESCAPED_PLAN\"," >> $TEMP_JSON
echo "  \"screenshot_path\": \"/sdcard/task_final_state.png\"" >> $TEMP_JSON
echo "}" >> $TEMP_JSON

mv $TEMP_JSON $RESULT_JSON
chmod 666 $RESULT_JSON 2>/dev/null || true

echo "Result saved to $RESULT_JSON"
echo "=== Export complete ==="