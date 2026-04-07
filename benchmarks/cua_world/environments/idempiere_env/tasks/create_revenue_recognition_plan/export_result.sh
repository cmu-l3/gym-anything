#!/bin/bash
echo "=== Exporting create_revenue_recognition_plan results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Client ID
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then
    CLIENT_ID=11
fi

# Query the specific record created by the agent
# We look for the exact name '12 Month Subscription' in the GardenWorld client
# We select created timestamp to verify it was made during the task
QUERY="SELECT C_RevenueRecognition_ID, Name, Description, IsTimeBased, RecognitionFrequency, IsActive, Created, CreatedBy FROM C_RevenueRecognition WHERE Name='12 Month Subscription' AND AD_Client_ID=$CLIENT_ID ORDER BY Created DESC LIMIT 1"

# Execute query using the helper
# format: ID|Name|Description|IsTimeBased|Frequency|IsActive|Created|CreatedBy
RECORD_DATA=$(docker exec idempiere-postgres psql -U adempiere -d idempiere -t -A -F"|" -c "$QUERY" 2>/dev/null || echo "")

echo "Database Record Found: $RECORD_DATA"

# Parse the pipe-separated result
# Note: Description might contain spaces, but pipes separate fields reliably here
REC_ID=$(echo "$RECORD_DATA" | cut -d'|' -f1)
REC_NAME=$(echo "$RECORD_DATA" | cut -d'|' -f2)
REC_DESC=$(echo "$RECORD_DATA" | cut -d'|' -f3)
REC_TIMEBASED=$(echo "$RECORD_DATA" | cut -d'|' -f4)
REC_FREQ=$(echo "$RECORD_DATA" | cut -d'|' -f5)
REC_ACTIVE=$(echo "$RECORD_DATA" | cut -d'|' -f6)
REC_CREATED=$(echo "$RECORD_DATA" | cut -d'|' -f7)

# Check if record was created during task window
# We can't easily compare SQL timestamp to unix timestamp in bash accurately without python,
# so we'll pass the raw SQL timestamp to python verifier or just rely on existence + logic.
# However, we can check if a record exists at all.
if [ -n "$REC_ID" ]; then
    RECORD_EXISTS="true"
else
    RECORD_EXISTS="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_exists": $RECORD_EXISTS,
    "record": {
        "id": "$REC_ID",
        "name": "$REC_NAME",
        "description": "$REC_DESC",
        "is_time_based": "$REC_TIMEBASED",
        "frequency": "$REC_FREQ",
        "is_active": "$REC_ACTIVE",
        "created_timestamp": "$REC_CREATED"
    },
    "client_id": $CLIENT_ID
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="