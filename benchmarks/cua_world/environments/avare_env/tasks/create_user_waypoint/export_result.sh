#!/system/bin/sh
echo "=== Exporting create_user_waypoint results ==="

# 1. Take final screenshot for visual verification
screencap -p /sdcard/task_final.png

# 2. Capture App State (Running?)
APP_RUNNING="false"
if ps -A | grep -q "com.ds.avare"; then
    APP_RUNNING="true"
fi

# 3. Locate and Copy the UDW.csv file
# Avare typically stores this in the user-selected Map Data Folder.
# We check common default locations.

UDW_FOUND="false"
UDW_PATH=""
TARGET_UDW="/sdcard/task_result_UDW.csv"

# Potential paths
PATHS="/sdcard/com.ds.avare/UDW.csv /sdcard/Android/data/com.ds.avare/files/UDW.csv /data/data/com.ds.avare/files/UDW.csv"

for p in $PATHS; do
    if [ -f "$p" ]; then
        echo "Found UDW file at $p"
        cp "$p" "$TARGET_UDW"
        # If it was in /data/data, we might need run-as, but we are root or shell user here usually
        if [ ! -f "$TARGET_UDW" ]; then
             # Try via cat/redirection if cp fails due to cross-device issues
             cat "$p" > "$TARGET_UDW"
        fi
        
        if [ -f "$TARGET_UDW" ]; then
            UDW_FOUND="true"
            UDW_PATH="$p"
            break
        fi
    fi
done

# 4. Get UDW File Content (for simple JSON inclusion if small)
UDW_CONTENT=""
if [ "$UDW_FOUND" = "true" ]; then
    # Read first few lines
    UDW_CONTENT=$(head -n 10 "$TARGET_UDW")
fi

# 5. Create Result JSON
# We write to a temp file then move to ensure atomicity
JSON_PATH="/sdcard/task_result.json"
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

echo "{" > "$JSON_PATH"
echo "  \"task_start\": $START_TIME," >> "$JSON_PATH"
echo "  \"task_end\": $END_TIME," >> "$JSON_PATH"
echo "  \"app_was_running\": $APP_RUNNING," >> "$JSON_PATH"
echo "  \"udw_file_found\": $UDW_FOUND," >> "$JSON_PATH"
echo "  \"udw_original_path\": \"$UDW_PATH\"," >> "$JSON_PATH"
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"" >> "$JSON_PATH"
echo "}" >> "$JSON_PATH"

echo "=== Export complete ==="
cat "$JSON_PATH"