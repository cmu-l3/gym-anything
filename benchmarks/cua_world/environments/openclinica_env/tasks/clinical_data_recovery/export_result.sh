#!/bin/bash
echo "=== Exporting clinical_data_recovery result ==="

source /workspace/scripts/task_utils.sh

# Capture final state
take_screenshot /tmp/task_end_screenshot.png

# Resolve Study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")

# Check Subject DM-106 Status
DM106_STATUS_ID=$(oc_query "SELECT status_id FROM study_subject WHERE label = 'DM-106' AND study_id = $DM_STUDY_ID LIMIT 1")
echo "DM-106 status_id: ${DM106_STATUS_ID:-not_found}"

# Check DM-102 Event Status
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")

DM102_EVENT_STATUS_ID="not_found"
if [ -n "$DM102_SS_ID" ] && [ -n "$WEEK4_SED_ID" ]; then
    DM102_EVENT_STATUS_ID=$(oc_query "SELECT status_id FROM study_event WHERE study_subject_id = $DM102_SS_ID AND study_event_definition_id = $WEEK4_SED_ID LIMIT 1")
fi
echo "DM-102 Event status_id: ${DM102_EVENT_STATUS_ID:-not_found}"

# Check Audit Log changes
AUDIT_CURRENT=$(oc_query "SELECT COUNT(*) FROM audit_log_event")
AUDIT_BASELINE=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit events: Current=${AUDIT_CURRENT:-0}, Baseline=${AUDIT_BASELINE:-0}"

# Bundle results into JSON
TEMP_JSON=$(mktemp /tmp/recovery_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm106_status_id": "${DM106_STATUS_ID:-not_found}",
    "dm102_event_status_id": "${DM102_EVENT_STATUS_ID:-not_found}",
    "audit_baseline": ${AUDIT_BASELINE:-0},
    "audit_current": ${AUDIT_CURRENT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Use safe move semantics
rm -f /tmp/clinical_data_recovery_result.json 2>/dev/null || sudo rm -f /tmp/clinical_data_recovery_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/clinical_data_recovery_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/clinical_data_recovery_result.json
chmod 666 /tmp/clinical_data_recovery_result.json 2>/dev/null || sudo chmod 666 /tmp/clinical_data_recovery_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/clinical_data_recovery_result.json"
echo "=== Export complete ==="