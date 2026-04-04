#!/bin/bash
set -e
echo "=== Exporting verify_tcp_options_mtu results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PCAP_PATH="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
REPORT_PATH="/home/ga/Documents/captures/tcp_options_report.txt"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Ground Truth using tshark (Performed here to keep verifier lightweight/independent)
echo "Calculating ground truth..."

# Extract Client MSS and WScale (Stream 0, SYN, Not ACK)
CLIENT_DATA=$(tshark -r "$PCAP_PATH" -Y "tcp.stream==0 && tcp.flags.syn==1 && tcp.flags.ack==0" -T fields -e tcp.options.mss_val -e tcp.options.wscale.shift 2>/dev/null | head -n 1)
GT_CLIENT_MSS=$(echo "$CLIENT_DATA" | awk '{print $1}')
GT_CLIENT_WSCALE=$(echo "$CLIENT_DATA" | awk '{print $2}')

# Extract Server MSS and WScale (Stream 0, SYN, ACK)
SERVER_DATA=$(tshark -r "$PCAP_PATH" -Y "tcp.stream==0 && tcp.flags.syn==1 && tcp.flags.ack==1" -T fields -e tcp.options.mss_val -e tcp.options.wscale.shift 2>/dev/null | head -n 1)
GT_SERVER_MSS=$(echo "$SERVER_DATA" | awk '{print $1}')
GT_SERVER_WSCALE=$(echo "$SERVER_DATA" | awk '{print $2}')

# Extract Max Payload Size (Stream 0)
GT_MAX_PAYLOAD=$(tshark -r "$PCAP_PATH" -Y "tcp.stream==0" -T fields -e tcp.len 2>/dev/null | sort -rn | head -n 1)

# Determine TSO Logic (True if Max Payload > min(Client_MSS, Server_MSS))
# Handle potential missing values (default to 1460 if not found, though they should be there)
SAFE_CLIENT_MSS=${GT_CLIENT_MSS:-1460}
SAFE_SERVER_MSS=${GT_SERVER_MSS:-1460}

# Find minimum MSS
if [ "$SAFE_CLIENT_MSS" -lt "$SAFE_SERVER_MSS" ]; then
    NEGOTIATED_MSS=$SAFE_CLIENT_MSS
else
    NEGOTIATED_MSS=$SAFE_SERVER_MSS
fi

# Compare
GT_TSO="NO"
if [ "$GT_MAX_PAYLOAD" -gt "$NEGOTIATED_MSS" ]; then
    GT_TSO="YES"
fi

echo "Ground Truth: CMSS=$GT_CLIENT_MSS, SMSS=$GT_SERVER_MSS, CW=$GT_CLIENT_WSCALE, SW=$GT_SERVER_WSCALE, MAX=$GT_MAX_PAYLOAD, TSO=$GT_TSO"

# 3. Process User Report
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
USER_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content
    USER_CONTENT=$(cat "$REPORT_PATH")
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use python to safely construct JSON
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_created_during_task': '$REPORT_CREATED_DURING_TASK' == 'true',
    'app_running': '$APP_RUNNING' == 'true',
    'ground_truth': {
        'client_mss': '$GT_CLIENT_MSS',
        'server_mss': '$GT_SERVER_MSS',
        'client_wscale': '$GT_CLIENT_WSCALE',
        'server_wscale': '$GT_SERVER_WSCALE',
        'max_payload': '$GT_MAX_PAYLOAD',
        'tso_detected': '$GT_TSO'
    },
    'user_content_raw': sys.stdin.read()
}
print(json.dumps(data))
" <<EOF > "$TEMP_JSON"
$USER_CONTENT
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="