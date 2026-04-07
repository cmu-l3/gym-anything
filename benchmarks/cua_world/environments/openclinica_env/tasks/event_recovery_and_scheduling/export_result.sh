#!/bin/bash
echo "=== Exporting event_recovery_and_scheduling result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Get DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

# Get DM-105 study_subject_id
DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")

# Get Event Definition IDs
M3_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Month 3 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
M6_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Month 6 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

# 1. Check Month 3 Event status
M3_EVENT_STATUS="5"
if [ -n "$DM105_SS_ID" ] && [ -n "$M3_SED_ID" ]; then
    M3_EVENT_STATUS=$(oc_query "SELECT status_id FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $M3_SED_ID ORDER BY study_event_id DESC LIMIT 1")
fi

# 2. Check Month 6 Event schedule
M6_EVENT_FOUND="false"
M6_EVENT_DATE=""
if [ -n "$DM105_SS_ID" ] && [ -n "$M6_SED_ID" ]; then
    M6_EVENT_DATA=$(oc_query "SELECT study_event_id, start_date, status_id FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $M6_SED_ID AND status_id != 5 ORDER BY study_event_id DESC LIMIT 1")
    if [ -n "$M6_EVENT_DATA" ]; then
        M6_EVENT_FOUND="true"
        M6_EVENT_DATE=$(echo "$M6_EVENT_DATA" | cut -d'|' -f2)
    fi
fi

# 3. Check Discrepancy Note
NOTE_FOUND="false"
NOTE_TYPE="0"
NOTE_DESC=""
NOTE_DATA=$(oc_query "SELECT discrepancy_note_type_id, description, detailed_notes FROM discrepancy_note WHERE LOWER(description) LIKE '%restored month 3%' OR LOWER(detailed_notes) LIKE '%restored month 3%' ORDER BY discrepancy_note_id DESC LIMIT 1")
if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
    NOTE_TYPE=$(echo "$NOTE_DATA" | cut -d'|' -f1)
    NOTE_DESC=$(echo "$NOTE_DATA" | cut -d'|' -f2)
fi

# Audit log count
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "m3_event_status": "${M3_EVENT_STATUS:-5}",
    "m6_event_found": $M6_EVENT_FOUND,
    "m6_event_date": "$(json_escape "${M6_EVENT_DATE:-}")",
    "note_found": $NOTE_FOUND,
    "note_type_id": "${NOTE_TYPE:-0}",
    "note_description": "$(json_escape "${NOTE_DESC:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')"
}
EOF

rm -f /tmp/event_recovery_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/event_recovery_result.json
chmod 666 /tmp/event_recovery_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="