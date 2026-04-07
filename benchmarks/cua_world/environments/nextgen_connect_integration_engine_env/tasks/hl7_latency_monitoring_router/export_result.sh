#!/bin/bash
echo "=== Exporting HL7 Latency Monitoring Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Functional Testing (Black Box)
# We will send test messages to the agent's channel and verify where they end up.

# Define timestamps
NOW_TS=$(date "+%Y%m%d%H%M%S")
# 20 minutes ago (High Latency)
HIGH_LATENCY_TS=$(date -d "20 minutes ago" "+%Y%m%d%H%M%S")
# 2 minutes ago (Normal Latency)
NORMAL_LATENCY_TS=$(date -d "2 minutes ago" "+%Y%m%d%H%M%S")

# Create Test Messages
# Message A: High Latency (MSH=Now, EVN=20 mins ago)
MSG_HIGH=$(printf "MSH|^~\\&|HIS|HOSPITAL|MIE|HUB|%s||ADT^A01|MSG001|P|2.3\rEVN|A01|%s\rPID|1||12345^^^MRN||DOE^HIGH" "$NOW_TS" "$HIGH_LATENCY_TS")

# Message B: Normal Latency (MSH=Now, EVN=2 mins ago)
MSG_NORMAL=$(printf "MSH|^~\\&|HIS|HOSPITAL|MIE|HUB|%s||ADT^A01|MSG002|P|2.3\rEVN|A01|%s\rPID|1||67890^^^MRN||DOE^NORMAL" "$NOW_TS" "$NORMAL_LATENCY_TS")

# Send Messages via TCP/MLLP
echo "Sending test messages to port 6661..."

# Function to send MLLP message
send_mllp() {
    local msg="$1"
    # Wrap in VT (0x0b) ... FS CR (0x1c 0x0d)
    printf "\x0b%s\x1c\r" "$msg" | nc -w 2 localhost 6661
}

# Clear directories before test to ensure we catch ONLY new files from this test
rm -f /home/ga/latency_high/*
rm -f /home/ga/latency_normal/*

# Send messages
send_mllp "$MSG_HIGH"
sleep 1
send_mllp "$MSG_NORMAL"
sleep 2

# 3. Verify Routing
HIGH_COUNT=$(ls /home/ga/latency_high/ 2>/dev/null | wc -l)
NORMAL_COUNT=$(ls /home/ga/latency_normal/ 2>/dev/null | wc -l)

# Check content to confirm correct routing (grep for patient names)
HIGH_CORRECT=$(grep -l "DOE^HIGH" /home/ga/latency_high/* 2>/dev/null | wc -l)
NORMAL_CORRECT=$(grep -l "DOE^NORMAL" /home/ga/latency_normal/* 2>/dev/null | wc -l)

# Check for cross-contamination (wrong messages in folders)
HIGH_WRONG=$(grep -l "DOE^NORMAL" /home/ga/latency_high/* 2>/dev/null | wc -l)
NORMAL_WRONG=$(grep -l "DOE^HIGH" /home/ga/latency_normal/* 2>/dev/null | wc -l)

echo "Test Results:"
echo "High Latency Folder: $HIGH_COUNT files (Correct msg: $HIGH_CORRECT, Wrong msg: $HIGH_WRONG)"
echo "Normal Latency Folder: $NORMAL_COUNT files (Correct msg: $NORMAL_CORRECT, Wrong msg: $NORMAL_WRONG)"

# 4. Check Channel Configuration (Static Analysis)
CHANNEL_ID=$(get_channel_id "Latency_Monitor")
CHANNEL_DEPLOYED="false"
CHANNEL_EXISTS="false"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    STATUS=$(get_channel_status_api "$CHANNEL_ID")
    if [ "$STATUS" == "STARTED" ]; then
        CHANNEL_DEPLOYED="true"
    fi
fi

# 5. Create Result JSON
json_content=$(cat <<EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_deployed": $CHANNEL_DEPLOYED,
    "functional_test": {
        "high_latency_routed_correctly": $((HIGH_CORRECT > 0 && HIGH_WRONG == 0)),
        "normal_latency_routed_correctly": $((NORMAL_CORRECT > 0 && NORMAL_WRONG == 0)),
        "high_latency_count": $HIGH_COUNT,
        "normal_latency_count": $NORMAL_COUNT
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$json_content"
cat /tmp/task_result.json
echo "=== Export complete ==="