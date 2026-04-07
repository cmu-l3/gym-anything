#!/bin/bash
echo "=== Exporting log_concomitant_medications result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Resolve IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
DM104_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-104' AND study_id = $DM_STUDY_ID LIMIT 1")
CONMED_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Concomitant Medication' AND study_id = $DM_STUDY_ID LIMIT 1")

# Extract Event Data
EVENT_COUNT=0
EVENTS_DATA=""

if [ -n "$DM104_SS_ID" ] && [ -n "$CONMED_SED_ID" ]; then
    EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $DM104_SS_ID AND study_event_definition_id = $CONMED_SED_ID AND status_id != 3")
    
    # Get raw event data (start_date and location)
    EVENTS_DATA=$(oc_query "SELECT start_date, location FROM study_event WHERE study_subject_id = $DM104_SS_ID AND study_event_definition_id = $CONMED_SED_ID AND status_id != 3")
fi

echo "Found $EVENT_COUNT Concomitant Medication events for DM-104."
echo "Event Data:"
echo "$EVENTS_DATA"

# Determine if expected medications are present
LISINOPRIL_FOUND="false"
AMOXICILLIN_FOUND="false"

if echo "$EVENTS_DATA" | grep -qi "Lisinopril"; then
    LISINOPRIL_FOUND="true"
fi

if echo "$EVENTS_DATA" | grep -qi "Amoxicillin"; then
    AMOXICILLIN_FOUND="true"
fi

# Audit log count (anti-gaming)
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write to JSON using temp file strategy
TEMP_JSON=$(mktemp /tmp/log_conmeds_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "event_count": ${EVENT_COUNT:-0},
    "events_data_raw": "$(json_escape "${EVENTS_DATA:-}")",
    "lisinopril_found": $LISINOPRIL_FOUND,
    "amoxicillin_found": $AMOXICILLIN_FOUND,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/log_conmeds_result.json 2>/dev/null || sudo rm -f /tmp/log_conmeds_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/log_conmeds_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/log_conmeds_result.json
chmod 666 /tmp/log_conmeds_result.json 2>/dev/null || sudo chmod 666 /tmp/log_conmeds_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/log_conmeds_result.json"
cat /tmp/log_conmeds_result.json

echo "=== Export Complete ==="