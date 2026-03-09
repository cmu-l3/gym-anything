#!/bin/bash
set -e
echo "=== Exporting Configure Drop Compliance Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the final state of the campaign
echo "Querying database for campaign settings..."
QUERY_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT drop_call_seconds, safe_harbor_exten, safe_harbor_message, drop_lockout_time, safe_harbor_audio_field FROM vicidial_campaigns WHERE campaign_id='TESTCAMP';" 2>/dev/null || echo "QUERY_FAILED")

if [ "$QUERY_RESULT" = "QUERY_FAILED" ]; then
    echo "FATAL: Database query failed"
    DROP_SECONDS="0"
    SH_EXTEN=""
    SH_MESSAGE=""
    DROP_LOCKOUT="0"
    SH_AUDIO="NONE"
else
    # Parse tab-separated output
    DROP_SECONDS=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $1}')
    SH_EXTEN=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $2}')
    SH_MESSAGE=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $3}')
    DROP_LOCKOUT=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $4}')
    SH_AUDIO=$(echo "$QUERY_RESULT" | awk -F'\t' '{print $5}')
fi

# Check initial state for anti-gaming (did values change?)
INITIAL_CHECK_RAW=$(cat /tmp/initial_state_check.txt 2>/dev/null || echo "")
VALUES_CHANGED="false"
if [ "$INITIAL_CHECK_RAW" != "QUERY_FAILED" ] && [ -n "$INITIAL_CHECK_RAW" ]; then
    # Simple check: if current result doesn't match initial raw string (approximate)
    CURRENT_CHECK_RAW=$(echo "$QUERY_RESULT" | tr '\t' '|')
    if [ "$CURRENT_CHECK_RAW" != "$INITIAL_CHECK_RAW" ]; then
        VALUES_CHANGED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "drop_call_seconds": "$DROP_SECONDS",
    "safe_harbor_exten": "$SH_EXTEN",
    "safe_harbor_message": $(echo "$SH_MESSAGE" | jq -R .),
    "drop_lockout_time": "$DROP_LOCKOUT",
    "safe_harbor_audio_field": "$SH_AUDIO",
    "values_changed_from_initial": $VALUES_CHANGED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="