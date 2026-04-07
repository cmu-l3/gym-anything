#!/bin/bash
echo "=== Exporting REST API Task Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Active Verification ---

# 1. Check if port is listening
IS_LISTENING="false"
if netstat -tuln | grep -q ":6670 "; then
    IS_LISTENING="true"
fi

# 2. Test Positive Case (Existing Patient)
# Expect HTTP 200 and JSON with "John Doe"
TEST_MRN="MRN-1001"
HTTP_CODE_POS=$(curl -s -o /tmp/resp_pos.json -w "%{http_code}" "http://localhost:6670?mrn=${TEST_MRN}")
RESP_BODY_POS=$(cat /tmp/resp_pos.json)

# Check content
POS_SUCCESS="false"
if [ "$HTTP_CODE_POS" == "200" ]; then
    if echo "$RESP_BODY_POS" | grep -q "John Doe" && echo "$RESP_BODY_POS" | grep -q "Active"; then
        POS_SUCCESS="true"
    fi
fi

# 3. Test Negative Case (Missing Patient)
# Expect HTTP 404
TEST_MISSING="MRN-9999"
HTTP_CODE_NEG=$(curl -s -o /tmp/resp_neg.json -w "%{http_code}" "http://localhost:6670?mrn=${TEST_MISSING}")
RESP_BODY_NEG=$(cat /tmp/resp_neg.json)

NEG_SUCCESS="false"
if [ "$HTTP_CODE_NEG" == "404" ]; then
    NEG_SUCCESS="true"
fi

# 4. Test Dynamic Lookup (Anti-Gaming)
# Insert a brand new record directly into DB and query it immediately
# This ensures the agent is actually querying the DB and not hardcoding responses
DYNAMIC_MRN="MRN-DYNAMIC-$(date +%s)"
DYNAMIC_NAME="Dynamic User"
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "INSERT INTO hospital_patients (mrn, full_name, status) VALUES ('${DYNAMIC_MRN}', '${DYNAMIC_NAME}', 'Test');"

# Query the new record
HTTP_CODE_DYN=$(curl -s -o /tmp/resp_dyn.json -w "%{http_code}" "http://localhost:6670?mrn=${DYNAMIC_MRN}")
RESP_BODY_DYN=$(cat /tmp/resp_dyn.json)

DYN_SUCCESS="false"
if [ "$HTTP_CODE_DYN" == "200" ]; then
    if echo "$RESP_BODY_DYN" | grep -q "${DYNAMIC_NAME}"; then
        DYN_SUCCESS="true"
    fi
fi

# 5. Check Channel Status in API
CHANNEL_ID=$(get_channel_id "Patient_Status_API")
CHANNEL_STATUS="UNKNOWN"
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# Construct JSON Result
cat > /tmp/task_result.json <<EOF
{
    "is_listening": ${IS_LISTENING},
    "channel_id": "${CHANNEL_ID}",
    "channel_status": "${CHANNEL_STATUS}",
    "positive_test": {
        "http_code": "${HTTP_CODE_POS}",
        "success": ${POS_SUCCESS},
        "body_preview": "$(echo $RESP_BODY_POS | head -c 100)"
    },
    "negative_test": {
        "http_code": "${HTTP_CODE_NEG}",
        "success": ${NEG_SUCCESS},
        "body_preview": "$(echo $RESP_BODY_NEG | head -c 100)"
    },
    "dynamic_test": {
        "mrn": "${DYNAMIC_MRN}",
        "http_code": "${HTTP_CODE_DYN}",
        "success": ${DYN_SUCCESS},
        "body_preview": "$(echo $RESP_BODY_DYN | head -c 100)"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Output for log
cat /tmp/task_result.json
echo "=== Export complete ==="