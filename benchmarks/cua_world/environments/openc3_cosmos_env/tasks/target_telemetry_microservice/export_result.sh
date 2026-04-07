#!/bin/bash
echo "=== Exporting Target Telemetry Microservice Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if something is listening on port 8000
PORT_OPEN="false"
if ss -tln | grep -q ":8000 "; then
    PORT_OPEN="true"
fi
echo "Port 8000 open: $PORT_OPEN"

# 2. Initial query to the microservice and ground truth
HTTP_CODE_1="000"
RESP_1_FILE="/tmp/microservice_resp_1.txt"
rm -f "$RESP_1_FILE"

if [ "$PORT_OPEN" = "true" ]; then
    HTTP_CODE_1=$(curl -s -o "$RESP_1_FILE" -w "%{http_code}" --max-time 3 http://localhost:8000/api/inst/status || echo "000")
fi

TRUTH_TEMP1_1=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "null")
TRUTH_TEMP2_1=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "null")
TRUTH_CMD_1=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "null")

echo "Initial query - HTTP Code: $HTTP_CODE_1"
echo "Truth 1: T1=$TRUTH_TEMP1_1, T2=$TRUTH_TEMP2_1, CMD=$TRUTH_CMD_1"

# 3. Alter system state (send a command to increment CMD_ACPT_CNT)
echo "Sending INST COLLECT command to alter state..."
cosmos_cmd "INST COLLECT with TYPE NORMAL, DURATION 1.0" 2>/dev/null || true

# Wait for command to be processed and telemetry to update
sleep 3

# 4. Secondary query to verify dynamic update
HTTP_CODE_2="000"
RESP_2_FILE="/tmp/microservice_resp_2.txt"
rm -f "$RESP_2_FILE"

if [ "$PORT_OPEN" = "true" ]; then
    HTTP_CODE_2=$(curl -s -o "$RESP_2_FILE" -w "%{http_code}" --max-time 3 http://localhost:8000/api/inst/status || echo "000")
fi

TRUTH_TEMP1_2=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "null")
TRUTH_TEMP2_2=$(cosmos_tlm "INST HEALTH_STATUS TEMP2" 2>/dev/null || echo "null")
TRUTH_CMD_2=$(cosmos_tlm "INST HEALTH_STATUS CMD_ACPT_CNT" 2>/dev/null || echo "null")

echo "Secondary query - HTTP Code: $HTTP_CODE_2"
echo "Truth 2: T1=$TRUTH_TEMP1_2, T2=$TRUTH_TEMP2_2, CMD=$TRUTH_CMD_2"

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Base64 encode responses to prevent JSON formatting errors in bash script assembly
B64_RESP_1=$(cat "$RESP_1_FILE" 2>/dev/null | base64 -w 0 || echo "")
B64_RESP_2=$(cat "$RESP_2_FILE" 2>/dev/null | base64 -w 0 || echo "")

# 7. Write consolidated JSON test results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "port_open": $PORT_OPEN,
    "query_1": {
        "http_code": "$HTTP_CODE_1",
        "response_b64": "$B64_RESP_1",
        "truth_temp1": $TRUTH_TEMP1_1,
        "truth_temp2": $TRUTH_TEMP2_1,
        "truth_cmd_cnt": $TRUTH_CMD_1
    },
    "query_2": {
        "http_code": "$HTTP_CODE_2",
        "response_b64": "$B64_RESP_2",
        "truth_temp1": $TRUTH_TEMP1_2,
        "truth_temp2": $TRUTH_TEMP2_2,
        "truth_cmd_cnt": $TRUTH_CMD_2
    }
}
EOF

# Move to final location safely
rm -f /tmp/microservice_test_result.json 2>/dev/null || sudo rm -f /tmp/microservice_test_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/microservice_test_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/microservice_test_result.json
chmod 666 /tmp/microservice_test_result.json 2>/dev/null || sudo chmod 666 /tmp/microservice_test_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="