#!/bin/bash
echo "=== Exporting Regex Router Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Trigger the Black Box Test (Send messages to the agent's channel)
echo "Running functional test suite..."

# Define MLLP bytes
SB='\x0b'
EB='\x1c\x0d'

# Test Case A: VALID (999999)
echo "Sending Test A (Valid)..."
MSG_VALID="MSH|^~\\&|TEST|SRC|DEST|REC|20240101||ADT^A01|TEST001|P|2.3"$'\r'"EVN|A01|20240101"$'\r'"PID|1||999999^^^MRN||VALID^TEST"
printf "${SB}${MSG_VALID}${EB}" | nc -w 2 localhost 6661 || true
sleep 2

# Test Case B: INVALID (BAD123)
echo "Sending Test B (Invalid)..."
MSG_INVALID="MSH|^~\\&|TEST|SRC|DEST|REC|20240101||ADT^A01|TEST002|P|2.3"$'\r'"EVN|A01|20240101"$'\r'"PID|1||BAD123^^^MRN||INVALID^TEST"
printf "${SB}${MSG_INVALID}${EB}" | nc -w 2 localhost 6661 || true
sleep 3

# 2. Inspect Output Directories
echo "Inspecting outputs..."

# Check Valid Directory
VALID_FILE=$(ls -t /home/ga/valid/ | head -n 1)
VALID_CONTENT=""
if [ -n "$VALID_FILE" ]; then
    VALID_CONTENT=$(cat "/home/ga/valid/$VALID_FILE")
fi

# Check Quarantine Directory
QUARANTINE_FILE=$(ls -t /home/ga/quarantine/ | head -n 1)
QUARANTINE_CONTENT=""
if [ -n "$QUARANTINE_FILE" ]; then
    QUARANTINE_CONTENT=$(cat "/home/ga/quarantine/$QUARANTINE_FILE")
fi

# 3. Get Channel Status via API
CHANNEL_STATUS="UNKNOWN"
CHANNEL_ID=""
CHANNELS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" https://localhost:8443/api/channels)
# Use python to find the ID of "MRN_Quality_Firewall"
CHANNEL_ID=$(echo "$CHANNELS_JSON" | python3 -c "import sys, json; 
try:
    data = json.load(sys.stdin)
    for c in data.get('list', []):
        if c.get('name') == 'MRN_Quality_Firewall':
            print(c.get('id'))
            break
except: pass" 2>/dev/null)

if [ -n "$CHANNEL_ID" ]; then
    STATUS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" https://localhost:8443/api/channels/$CHANNEL_ID/status)
    CHANNEL_STATUS=$(echo "$STATUS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('dashboardStatus', {}).get('state', 'UNKNOWN'))" 2>/dev/null)
fi

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_status": "$CHANNEL_STATUS",
    "test_a_valid_file_exists": $([ -n "$VALID_FILE" ] && echo "true" || echo "false"),
    "test_a_content_sample": "$(echo "$VALID_CONTENT" | head -c 200 | sed 's/"/\\"/g')",
    "test_b_quarantine_file_exists": $([ -n "$QUARANTINE_FILE" ] && echo "true" || echo "false"),
    "test_b_content_sample": "$(echo "$QUARANTINE_CONTENT" | head -c 200 | sed 's/"/\\"/g')",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json