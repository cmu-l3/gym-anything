#!/bin/bash
echo "=== Exporting Secure HMAC Webhook Receiver Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Functional Testing Script
# We will simulate the sender (CloudBook) to verify the channel logic
echo "Starting functional verification tests..."

# Configuration
TARGET_URL="http://localhost:6675"
SECRET="HealthSecure2025"
OUTPUT_DIR="/home/ga/appointments"
TEST_PAYLOAD='{"test":"functional_verification","timestamp":'$(date +%s)'}'

# Helper python script to generate HMAC signature
generate_signature() {
    local payload="$1"
    local secret="$2"
    python3 -c "import hmac, hashlib; print(hmac.new('$secret'.encode(), '$payload'.encode(), hashlib.sha256).hexdigest())"
}

# Clear output dir before testing to ensure we count ONLY our test files
# (Agent might have created files during their own testing)
# We back them up first just in case
mkdir -p /tmp/agent_artifacts
mv "$OUTPUT_DIR"/* /tmp/agent_artifacts/ 2>/dev/null

# --- TEST CASE 1: Valid Signature ---
echo "Test 1: Sending Valid Request..."
VALID_SIG=$(generate_signature "$TEST_PAYLOAD" "$SECRET")
HTTP_CODE_1=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-Signature: $VALID_SIG" -d "$TEST_PAYLOAD" "$TARGET_URL")
sleep 2 # Wait for file write
FILE_COUNT_1=$(ls -1 "$OUTPUT_DIR" | wc -l)

# --- TEST CASE 2: Tampered Payload ---
echo "Test 2: Sending Tampered Request (Signature mismatch)..."
# Signature matches "original", but we send "modified"
TAMPERED_PAYLOAD='{"test":"hacked"}'
HTTP_CODE_2=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "X-Signature: $VALID_SIG" -d "$TAMPERED_PAYLOAD" "$TARGET_URL")
sleep 1
FILE_COUNT_2=$(ls -1 "$OUTPUT_DIR" | wc -l) # Should not increase from FILE_COUNT_1

# --- TEST CASE 3: Missing Header ---
echo "Test 3: Sending Unsigned Request..."
HTTP_CODE_3=$(curl -s -o /dev/null -w "%{http_code}" -X POST -d "$TEST_PAYLOAD" "$TARGET_URL")
sleep 1
FILE_COUNT_3=$(ls -1 "$OUTPUT_DIR" | wc -l) # Should not increase

# 3. Channel Configuration Inspection
echo "Inspecting channel configuration..."
CHANNEL_FOUND="false"
CHANNEL_NAME=""
PORT_CONFIGURED="false"
SOURCE_FILTER_EXISTS="false"

# Get all channels
CHANNELS_JSON=$(get_channels_api)

# Look for our channel
if [ -n "$CHANNELS_JSON" ]; then
    # We use python to parse the complex JSON/XML structure logic
    # Find channel ID by name
    CHANNEL_ID=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
channels = data.get('list', {}).get('channel', [])
if isinstance(channels, dict): channels = [channels] # Handle single entry case
found_id = ''
for c in channels:
    if 'CloudBook_Webhook' in c.get('name', ''):
        found_id = c.get('id')
        break
print(found_id)
")
    
    if [ -n "$CHANNEL_ID" ]; then
        CHANNEL_FOUND="true"
        
        # Get specific channel details
        CHANNEL_DETAILS=$(api_call_json GET "/channels/$CHANNEL_ID")
        
        # Check Source Connector (HTTP Listener on 6675)
        PORT_CONFIGURED=$(echo "$CHANNEL_DETAILS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
props = data.get('sourceConnector', {}).get('properties', {}).get('listenerConnectorProperties', {})
print('true' if props.get('port') == '6675' else 'false')
")

        # Check for existence of Filter script
        SOURCE_FILTER_EXISTS=$(echo "$CHANNEL_DETAILS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
filter_type = data.get('sourceConnector', {}).get('filter', {}).get('elements', {})
# In Mirth, filters can be RuleBuilder or JavaScript. We look for non-empty logic.
# A simple check is if the XML/JSON structure has content.
print('true' if str(filter_type) != 'None' and len(str(filter_type)) > 10 else 'false')
")
        
        # Check Deployment Status
        STATUS=$(get_channel_status_api "$CHANNEL_ID")
    fi
fi

# 4. Generate Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "channel_found": $CHANNEL_FOUND,
    "channel_id": "$CHANNEL_ID",
    "port_correct": $PORT_CONFIGURED,
    "filter_exists": $SOURCE_FILTER_EXISTS,
    "channel_status": "$STATUS",
    "tests": {
        "valid_req": {
            "http_code": "$HTTP_CODE_1",
            "files_after": $FILE_COUNT_1,
            "passed": $([ "$FILE_COUNT_1" -ge 1 ] && echo "true" || echo "false")
        },
        "tampered_req": {
            "http_code": "$HTTP_CODE_2",
            "files_after": $FILE_COUNT_2,
            "passed": $([ "$FILE_COUNT_2" -eq "$FILE_COUNT_1" ] && echo "true" || echo "false")
        },
        "unsigned_req": {
            "http_code": "$HTTP_CODE_3",
            "files_after": $FILE_COUNT_3,
            "passed": $([ "$FILE_COUNT_3" -eq "$FILE_COUNT_1" ] && echo "true" || echo "false")
        }
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Result Export Complete."
cat /tmp/task_result.json