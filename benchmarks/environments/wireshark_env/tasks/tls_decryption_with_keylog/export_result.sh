#!/bin/bash
set -e
echo "=== Exporting TLS Decryption results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_PATH="/home/ga/Documents/decrypted_flag.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
USER_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    USER_CONTENT=$(cat "$OUTPUT_PATH" | tr -d '[:space:]') # Strip whitespace
    
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Get Ground Truth
GROUND_TRUTH_PATH="/var/lib/app/ground_truth/secret_uuid.txt"
GROUND_TRUTH=$(cat "$GROUND_TRUTH_PATH" 2>/dev/null || echo "")

# 3. Check if Wireshark is configured (Check 'recent' file or preferences)
# We can grep the preferences file to see if tls.keylog_file is set
PREF_CHECK="false"
if grep -q "tls.keylog_file" /home/ga/.config/wireshark/recent 2>/dev/null; then
    PREF_CHECK="true"
fi
if grep -q "tls.keylog_file" /home/ga/.config/wireshark/preferences 2>/dev/null; then
    PREF_CHECK="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
data = {
    'task_start': int(sys.argv[1]),
    'task_end': int(sys.argv[2]),
    'output_exists': sys.argv[3] == 'true',
    'file_created_during_task': sys.argv[4] == 'true',
    'user_content': sys.argv[5],
    'ground_truth': sys.argv[6],
    'pref_configured': sys.argv[7] == 'true',
    'screenshot_path': '/tmp/task_final.png'
}
with open(sys.argv[8], 'w') as f:
    json.dump(data, f, indent=4)
" "$TASK_START" "$TASK_END" "$OUTPUT_EXISTS" "$FILE_CREATED_DURING_TASK" "$USER_CONTENT" "$GROUND_TRUTH" "$PREF_CHECK" "$TEMP_JSON"

# Move to final location safely
safe_json_write "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="