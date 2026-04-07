#!/system/bin/sh
echo "=== Exporting export_flight_plan_gpx results ==="

# 1. Define paths and times
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
EXPECTED_FILENAME="route_export.gpx"

# 2. Search for the exported file in likely locations
# Avare might save to root, Download, or its app folder
FOUND_PATH=""
FOUND_PATH=$(find /sdcard -name "$EXPECTED_FILENAME" | head -n 1)

FILE_EXISTS="false"
FILE_SIZE="0"
FILE_CONTENT_PREVIEW=""
FILE_CREATED_DURING_TASK="false"
FILE_HAS_GPX_TAG="false"
FILE_HAS_KRHV="false"
FILE_HAS_KMOD="false"

if [ -n "$FOUND_PATH" ]; then
    echo "Found file at: $FOUND_PATH"
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FOUND_PATH" 2>/dev/null || echo "0")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$FOUND_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check Content
    # Read first 50 lines to check for GPX structure and waypoints
    CONTENT=$(head -n 50 "$FOUND_PATH")
    
    if echo "$CONTENT" | grep -q "<gpx"; then
        FILE_HAS_GPX_TAG="true"
    fi
    if echo "$CONTENT" | grep -q "KRHV"; then
        FILE_HAS_KRHV="true"
    fi
    if echo "$CONTENT" | grep -q "KMOD"; then
        FILE_HAS_KMOD="true"
    fi
    
    # Save a preview for the verifier (base64 encoded to avoid JSON issues)
    # On Android simplified sh, base64 might need specific handling or just save raw text
    # We will just save validity flags to JSON to keep it simple and robust
fi

# 3. Take final screenshot
screencap -p /sdcard/task_final.png

# 4. Create JSON result
# Note: Android's native sh printf is limited, using simple echo
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_path\": \"$FOUND_PATH\"," >> /sdcard/task_result.json
echo "  \"file_size\": $FILE_SIZE," >> /sdcard/task_result.json
echo "  \"created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"content_check\": {" >> /sdcard/task_result.json
echo "    \"has_gpx_tag\": $FILE_HAS_GPX_TAG," >> /sdcard/task_result.json
echo "    \"has_krhv\": $FILE_HAS_KRHV," >> /sdcard/task_result.json
echo "    \"has_kmod\": $FILE_HAS_KMOD" >> /sdcard/task_result.json
echo "  }," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "=== Export complete ==="
cat /sdcard/task_result.json