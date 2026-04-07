#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
OUTPUT_FILE="/var/www/html/dashboard.html"
TEST_OUTPUT_1="/tmp/dashboard_snapshot_1.html"
TEST_OUTPUT_2="/tmp/dashboard_snapshot_2.html"

# Verify file existence
if [ -f "$OUTPUT_FILE" ]; then
    echo "Dashboard file found."
    OUTPUT_EXISTS="true"
    cp "$OUTPUT_FILE" "$TEST_OUTPUT_1"
else
    echo "Dashboard file NOT found."
    OUTPUT_EXISTS="false"
    # Create empty file to avoid errors in python script
    touch "$TEST_OUTPUT_1"
fi

# Get current channel stats via API for reference
STATS_JSON_1=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/statistics")
echo "$STATS_JSON_1" > /tmp/stats_1.json

# --- DYNAMIC VERIFICATION STEP ---
# Inject more traffic to change the stats
echo "Injecting verification traffic..."
# 3 messages to ADT (9001)
for i in {1..3}; do
    printf '\x0bMSH|^~\\&|VERIFY|FAC|REC|FAC|202301010000||ADT^A01|MSG_V_1|P|2.3\r\x1c\x0d' | nc localhost 9001
    sleep 0.1
done
# 2 messages to Lab (9002)
for i in {1..2}; do
    printf '\x0bMSH|^~\\&|VERIFY|FAC|REC|FAC|202301010000||ORU^R01|MSG_V_2|P|2.3\r\x1c\x0d' | nc localhost 9002
    sleep 0.1
done

# Wait for agent's channel to poll (Task requires 30s poll, so wait 40s)
echo "Waiting 40s for dashboard update..."
sleep 40

# Capture second snapshot
if [ -f "$OUTPUT_FILE" ]; then
    cp "$OUTPUT_FILE" "$TEST_OUTPUT_2"
else
    touch "$TEST_OUTPUT_2"
fi

# Get new API stats
STATS_JSON_2=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" -H "Accept: application/json" "https://localhost:8443/api/channels/statistics")
echo "$STATS_JSON_2" > /tmp/stats_2.json

# Check if agent's channel exists and is started
AGENT_CHANNEL_ID=$(get_channel_id "Ops_Dashboard_Generator")
AGENT_CHANNEL_STATUS="UNKNOWN"
if [ -n "$AGENT_CHANNEL_ID" ]; then
    AGENT_CHANNEL_STATUS=$(get_channel_status_api "$AGENT_CHANNEL_ID")
fi

echo "Agent Channel ID: $AGENT_CHANNEL_ID"
echo "Agent Channel Status: $AGENT_CHANNEL_STATUS"

# Package everything into a JSON
python3 -c "
import json
import os

def read_file(path):
    try:
        with open(path, 'r') as f: return f.read()
    except: return ''

data = {
    'output_exists': '$OUTPUT_EXISTS' == 'true',
    'agent_channel_status': '$AGENT_CHANNEL_STATUS',
    'html_snapshot_1': read_file('$TEST_OUTPUT_1'),
    'html_snapshot_2': read_file('$TEST_OUTPUT_2'),
    'api_stats_1': read_file('/tmp/stats_1.json'),
    'api_stats_2': read_file('/tmp/stats_2.json'),
    'timestamp': '$(date)'
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
"

# Copy output to artifact location
cp /tmp/task_result.json /tmp/export_result.json 2>/dev/null || true
chmod 666 /tmp/export_result.json 2>/dev/null || true

cat /tmp/task_result.json | head -c 200
echo "... (truncated)"
echo "=== Export complete ==="