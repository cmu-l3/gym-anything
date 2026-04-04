#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_FILE="/home/ga/Documents/telnet_report.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    CONTENT=$(cat "$OUTPUT_FILE")
fi

# 2. Get Ground Truth (hidden)
GT_FILE="/var/lib/wireshark_ground_truth/credentials.txt"
GT_USERNAME=""
GT_PASSWORD=""

if [ -f "$GT_FILE" ]; then
    GT_USERNAME=$(grep "^username:" "$GT_FILE" | head -1 | cut -d: -f2- | sed 's/^[ \t]*//;s/[ \t]*$//')
    GT_PASSWORD=$(grep "^password:" "$GT_FILE" | head -1 | cut -d: -f2- | sed 's/^[ \t]*//;s/[ \t]*$//')
fi

# 3. Check Wireshark Usage (Process check)
WIRESHARK_RUNNING="false"
if pgrep -f "wireshark" > /dev/null; then
    WIRESHARK_RUNNING="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys

try:
    content = sys.argv[1]
    gt_user = sys.argv[2]
    gt_pass = sys.argv[3]
    
    # Simple parse of user content
    user_val = ''
    pass_val = ''
    
    for line in content.split('\n'):
        if line.lower().startswith('username:'):
            user_val = line.split(':', 1)[1].strip()
        elif line.lower().startswith('password:'):
            pass_val = line.split(':', 1)[1].strip()

    result = {
        'file_exists': sys.argv[4] == 'true',
        'file_created_during_task': sys.argv[5] == 'true',
        'wireshark_running': sys.argv[6] == 'true',
        'extracted_username': user_val,
        'extracted_password': pass_val,
        'gt_username': gt_user,
        'gt_password': gt_pass,
        'raw_content': content
    }
    
    with open(sys.argv[7], 'w') as f:
        json.dump(result, f, indent=2)

except Exception as e:
    print(json.dumps({'error': str(e)}))

" "$CONTENT" "$GT_USERNAME" "$GT_PASSWORD" "$FILE_EXISTS" "$FILE_CREATED_DURING_TASK" "$WIRESHARK_RUNNING" "$TEMP_JSON"

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="