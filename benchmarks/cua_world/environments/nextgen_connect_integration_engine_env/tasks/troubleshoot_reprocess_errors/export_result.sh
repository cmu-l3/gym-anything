#!/bin/bash
echo "=== Exporting Troubleshoot & Reprocess Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# API Credentials
API_URL="https://localhost:8443/api"
CREDS="-u admin:admin"
HEADER="-H X-Requested-With:OpenAPI"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Get Channel ID for 'ADT_State_Normalizer'
CHANNEL_ID=""
CHANNEL_DATA=$(curl -sk $CREDS $HEADER "$API_URL/channels" | grep -B 1 "ADT_State_Normalizer")
if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | grep -oP '<id>\K[^<]+')
fi

# 2. Get Channel Stats
STATS_RECEIVED=0
STATS_ERRORED=0
STATS_SENT=0
CHANNEL_STATE="UNKNOWN"

if [ -n "$CHANNEL_ID" ]; then
    # Stats
    STATS_JSON=$(curl -sk $CREDS $HEADER -H "Accept: application/json" "$API_URL/channels/$CHANNEL_ID/statistics")
    # Parse JSON for aggregate (metaDataId=0)
    STATS_RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((s.get('received',0) for s in d if s.get('metaDataId')==0), 0))" 2>/dev/null || echo "0")
    STATS_ERRORED=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((s.get('error',0) for s in d if s.get('metaDataId')==0), 0))" 2>/dev/null || echo "0")
    STATS_SENT=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((s.get('sent',0) for s in d if s.get('metaDataId')==0), 0))" 2>/dev/null || echo "0")

    # Status
    STATUS_JSON=$(curl -sk $CREDS $HEADER -H "Accept: application/json" "$API_URL/channels/$CHANNEL_ID/status")
    CHANNEL_STATE=$(echo "$STATUS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dashboardStatus', d).get('state', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
fi

# 3. Check Output Files
OUTPUT_DIR="/home/ga/normalized_adt"
OUTPUT_FILE_COUNT=$(ls -1 "$OUTPUT_DIR"/*.hl7 2>/dev/null | wc -l)

# 4. Check Content for "UNKNOWN"
# This verifies the fix logic (mapping unknown states to "UNKNOWN")
CONTENT_FIX_VERIFIED="false"
if grep -q "UNKNOWN" "$OUTPUT_DIR"/*.hl7 2>/dev/null; then
    CONTENT_FIX_VERIFIED="true"
fi

# 5. Create Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_id": "$CHANNEL_ID",
    "channel_state": "$CHANNEL_STATE",
    "stats_received": $STATS_RECEIVED,
    "stats_errored": $STATS_ERRORED,
    "stats_sent": $STATS_SENT,
    "output_file_count": $OUTPUT_FILE_COUNT,
    "content_fix_verified": $CONTENT_FIX_VERIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="