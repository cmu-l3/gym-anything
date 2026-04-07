#!/bin/bash
echo "=== Exporting modify_event_definitions result ==="

source /workspace/scripts/task_utils.sh

# Final screenshot
take_screenshot /tmp/task_end_screenshot.png

# --- Retrieve IDs ---
ID_BL=$(cat /tmp/sed_id_bl.txt 2>/dev/null || echo "0")
ID_W4=$(cat /tmp/sed_id_w4.txt 2>/dev/null || echo "0")
ID_AE=$(cat /tmp/sed_id_ae.txt 2>/dev/null || echo "0")
ID_EOT=$(cat /tmp/sed_id_eot.txt 2>/dev/null || echo "0")

echo "IDs to check: BL=$ID_BL, W4=$ID_W4, AE=$ID_AE, EOT=$ID_EOT"

# Function to get safely delimited JSON data for an event definition
get_event_def_json() {
    local ed_id=$1
    if [ "$ed_id" = "0" ] || [ -z "$ed_id" ]; then
        echo '{"exists": false}'
        return
    fi

    # Query fields and construct JSON using PostgreSQL json_build_object
    local JSON_RESULT=$(oc_query "SELECT json_build_object(
        'exists', true,
        'name', name,
        'description', description,
        'repeating', repeating,
        'category', category,
        'type', type
    ) FROM study_event_definition WHERE study_event_definition_id = $ed_id")

    if [ -n "$JSON_RESULT" ]; then
        echo "$JSON_RESULT"
    else
        echo '{"exists": false}'
    fi
}

# --- Gather Data ---
JSON_BL=$(get_event_def_json $ID_BL)
JSON_W4=$(get_event_def_json $ID_W4)
JSON_AE=$(get_event_def_json $ID_AE)
JSON_EOT=$(get_event_def_json $ID_EOT)

# --- Check Audit Log ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count.txt 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# --- Construct Final Result JSON ---
TEMP_JSON=$(mktemp /tmp/modify_events_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $START_TIME,
    "task_end_time": $END_TIME,
    "audit_baseline": $AUDIT_BASELINE_COUNT,
    "audit_current": $AUDIT_LOG_COUNT,
    "result_nonce": "$NONCE",
    "events": {
        "baseline": $JSON_BL,
        "week4": $JSON_W4,
        "adverse_event": $JSON_AE,
        "end_of_treatment": $JSON_EOT
    }
}
EOF

# Move to final location safely
rm -f /tmp/modify_event_definitions_result.json 2>/dev/null || sudo rm -f /tmp/modify_event_definitions_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/modify_event_definitions_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/modify_event_definitions_result.json
chmod 666 /tmp/modify_event_definitions_result.json 2>/dev/null || sudo chmod 666 /tmp/modify_event_definitions_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/modify_event_definitions_result.json"
cat /tmp/modify_event_definitions_result.json
echo ""
echo "=== Export complete ==="