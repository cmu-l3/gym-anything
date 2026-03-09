#!/system/bin/sh
echo "=== Exporting Results ==="

# 1. Capture Final Screenshot
screencap -p /sdcard/final_screenshot.png
echo "Screenshot captured."

# 2. Check Output File
OUTPUT_FILE="/sdcard/mcrpc_therapy_choice.txt"
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}')
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# 3. Get Task Start Time
START_TIME=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

# 4. Create Result JSON
# Note: Android shell is limited, constructing JSON manually
echo "{" > /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_size\": $FILE_SIZE," >> /sdcard/task_result.json
echo "  \"start_time\": \"$START_TIME\"," >> /sdcard/task_result.json
echo "  \"file_content\": \"$FILE_CONTENT\"," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/final_screenshot.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

chmod 666 /sdcard/task_result.json
echo "Result JSON created at /sdcard/task_result.json"