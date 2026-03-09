#!/bin/bash
set -e

echo "=== Exporting follow_tcp_stream result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check if the user created the output file
OUTPUT_FILE=""
FILE_EXISTS="false"
CONTENT=""
CONTENT_LENGTH=0

for loc in /home/ga/Documents/captures/smtp_stream.txt /home/ga/Desktop/smtp_stream.txt /home/ga/smtp_stream.txt /tmp/smtp_stream.txt /home/ga/Documents/smtp_stream.txt; do
    if [ -f "$loc" ]; then
        FILE_EXISTS="true"
        OUTPUT_FILE="$loc"
        CONTENT=$(cat "$loc" 2>/dev/null || echo "")
        CONTENT_LENGTH=${#CONTENT}
        break
    fi
done

# Check for SMTP keywords in user's saved content
HAS_EHLO="false"
HAS_MAIL_FROM="false"
HAS_RCPT_TO="false"
HAS_DATA_CMD="false"
HAS_SMTP_RESPONSE="false"

if [ "$FILE_EXISTS" = "true" ] && [ -n "$CONTENT" ]; then
    echo "$CONTENT" | grep -qi "EHLO\|HELO" && HAS_EHLO="true"
    echo "$CONTENT" | grep -qi "MAIL FROM" && HAS_MAIL_FROM="true"
    echo "$CONTENT" | grep -qi "RCPT TO" && HAS_RCPT_TO="true"
    echo "$CONTENT" | grep -qi "^DATA\|^data" && HAS_DATA_CMD="true"
    echo "$CONTENT" | grep -q "^2[0-9][0-9] \|^3[0-9][0-9] " && HAS_SMTP_RESPONSE="true"
fi

# Create result JSON safely using python3
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
data = {
    'output_file_exists': sys.argv[1] == 'true',
    'output_file_path': sys.argv[2],
    'content_length': int(sys.argv[3]),
    'has_ehlo': sys.argv[4] == 'true',
    'has_mail_from': sys.argv[5] == 'true',
    'has_rcpt_to': sys.argv[6] == 'true',
    'has_data_command': sys.argv[7] == 'true',
    'has_smtp_response_codes': sys.argv[8] == 'true',
    'timestamp': sys.argv[9]
}
with open(sys.argv[10], 'w') as f:
    json.dump(data, f, indent=4)
" "$FILE_EXISTS" "$OUTPUT_FILE" "$CONTENT_LENGTH" "$HAS_EHLO" "$HAS_MAIL_FROM" "$HAS_RCPT_TO" "$HAS_DATA_CMD" "$HAS_SMTP_RESPONSE" "$(date -Iseconds)" "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
