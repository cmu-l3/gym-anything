#!/bin/bash
echo "=== Exporting ACK Capture Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Sample Data was processed (Static Check)
# ORD-001 was pre-loaded. If agent ran the sample file, this should be updated.
SAMPLE_REF=$(query_postgres "SELECT lab_reference_number FROM lab_orders WHERE order_control_id='ORD-001';" 2>/dev/null)
SAMPLE_UPDATED="false"
if [[ "$SAMPLE_REF" == *"LAB-REF-ORD-001"* ]]; then
    SAMPLE_UPDATED="true"
fi

# 2. Run Dynamic Test (Anti-Gaming & Robustness)
# We will inject a new order into the DB, send a message to the agent's channel, and check if it updates.
echo "Running dynamic verification..."
TEST_ID="ORD-TEST-$(date +%s)"
EXPECTED_REF="LAB-REF-$TEST_ID"

# Insert test record into DB
docker exec nextgen-postgres psql -U postgres -d mirthdb -c \
    "INSERT INTO lab_orders (order_control_id, patient_name) VALUES ('$TEST_ID', 'Test^Patient');"

# Construct HL7 message
# Note: We construct MLLP frame manually: \x0b + data + \x1c\x0d
TEST_MSG="MSH|^~\\&|TEST|TEST|LAB|SIM|$(date +%Y%m%d%H%M)||ORM^O01|$TEST_ID|P|2.3\rPID|1||999||Test^Patient\rORC|NW|$TEST_ID\r"

# Send to agent's listening port (6661)
# Timeout after 2 seconds
echo -e "\x0b${TEST_MSG}\x1c\r" | timeout 2 nc localhost 6661 > /tmp/ack_response.txt 2>/dev/null
NC_EXIT=$?

# Allow processing time
sleep 5

# Check Database for update
DYNAMIC_REF=$(query_postgres "SELECT lab_reference_number FROM lab_orders WHERE order_control_id='$TEST_ID';" 2>/dev/null)
DYNAMIC_SUCCESS="false"

if [[ "$DYNAMIC_REF" == *"$EXPECTED_REF"* ]]; then
    DYNAMIC_SUCCESS="true"
fi

# Check if channel port is open
CHANNEL_PORT_OPEN="false"
if netstat -tuln | grep -q ":6661 "; then
    CHANNEL_PORT_OPEN="true"
fi

# Get Lab Simulator status (is it still running?)
SIMULATOR_RUNNING="false"
if pgrep -f "lab_simulator.py" > /dev/null; then
    SIMULATOR_RUNNING="true"
fi

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "sample_updated": $SAMPLE_UPDATED,
    "sample_value": "$SAMPLE_REF",
    "dynamic_test_id": "$TEST_ID",
    "dynamic_test_success": $DYNAMIC_SUCCESS,
    "dynamic_value_found": "$DYNAMIC_REF",
    "expected_dynamic_value": "$EXPECTED_REF",
    "channel_port_open": $CHANNEL_PORT_OPEN,
    "simulator_running": $SIMULATOR_RUNNING,
    "nc_exit_code": $NC_EXIT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="