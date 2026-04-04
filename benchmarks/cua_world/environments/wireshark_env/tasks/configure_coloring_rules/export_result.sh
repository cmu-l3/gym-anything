#!/bin/bash
set -e

echo "=== Exporting configure_coloring_rules result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (System level)
take_screenshot /tmp/task_final.png

# 2. Collect timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check for User Output File (Frame Number)
OUTPUT_FILE="/home/ga/Documents/rst_frame_number.txt"
USER_FRAME_NUMBER=""
OUTPUT_FILE_EXISTS="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_FILE_EXISTS="true"
    USER_FRAME_NUMBER=$(cat "$OUTPUT_FILE" | tr -d '[:space:]' | grep -oE '[0-9]+' || echo "")
fi

# 4. Check for User Screenshot
USER_SCREENSHOT="/home/ga/Documents/colored_packets.png"
USER_SCREENSHOT_EXISTS="false"
if [ -f "$USER_SCREENSHOT" ]; then
    USER_SCREENSHOT_EXISTS="true"
fi

# 5. Read the Coloring Rules Configuration
# Wireshark saves this to ~/.config/wireshark/coloringrules
CONFIG_FILE="/home/ga/.config/wireshark/coloringrules"
CONFIG_CONTENT=""
CONFIG_EXISTS="false"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    # Read content, escape double quotes and newlines for JSON
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0)
fi

# 6. Get Ground Truth
GROUND_TRUTH_FRAME=$(cat /tmp/ground_truth_rst_frame.txt 2>/dev/null || echo "0")

# 7. Check if Wireshark is currently running (not strictly required to be running at end, but good context)
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# 8. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys

data = {
    'task_start': int(sys.argv[1]),
    'task_end': int(sys.argv[2]),
    'output_file_exists': sys.argv[3] == 'true',
    'user_frame_number': sys.argv[4],
    'user_screenshot_exists': sys.argv[5] == 'true',
    'config_exists': sys.argv[6] == 'true',
    'config_content_b64': sys.argv[7],
    'ground_truth_frame': sys.argv[8],
    'app_running': sys.argv[9] == 'true'
}

with open(sys.argv[10], 'w') as f:
    json.dump(data, f, indent=4)
" "$TASK_START" "$TASK_END" "$OUTPUT_FILE_EXISTS" "$USER_FRAME_NUMBER" "$USER_SCREENSHOT_EXISTS" "$CONFIG_EXISTS" "$CONFIG_CONTENT" "$GROUND_TRUTH_FRAME" "$APP_RUNNING" "$TEMP_JSON"

# 9. Save result to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON content:"
cat /tmp/task_result.json
echo "=== Export complete ==="