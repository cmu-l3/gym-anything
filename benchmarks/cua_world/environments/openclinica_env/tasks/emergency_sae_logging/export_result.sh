#!/bin/bash
echo "=== Exporting emergency_sae_logging result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
DM105_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
SAE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Unscheduled SAE' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

HAS_UNBLINDING="false"
HAS_SAE="false"
EVENT_SCHEDULED="false"

if [ -n "$DM105_SS_ID" ]; then
    # Check Subject level notes
    NOTES_DATA=$(oc_query "SELECT description FROM discrepancy_note WHERE entity_type = 'studySubject' AND entity_id = $DM105_SS_ID")
    if echo "$NOTES_DATA" | grep -qi "unblinding"; then
        HAS_UNBLINDING="true"
    fi
    if echo "$NOTES_DATA" | grep -qi "severe hypoglycemia"; then
        HAS_SAE="true"
    fi
    
    # Check Event scheduling and Event level notes
    EVENT_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $DM105_SS_ID AND study_event_definition_id = $SAE_SED_ID LIMIT 1")
    if [ -n "$EVENT_ID" ]; then
        EVENT_SCHEDULED="true"
        EVENT_NOTES=$(oc_query "SELECT description FROM discrepancy_note WHERE entity_type = 'studyEvent' AND entity_id = $EVENT_ID")
        if echo "$EVENT_NOTES" | grep -qi "unblinding"; then
            HAS_UNBLINDING="true"
        fi
        if echo "$EVENT_NOTES" | grep -qi "severe hypoglycemia"; then
            HAS_SAE="true"
        fi
    fi
fi

AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

TEMP_JSON=$(mktemp /tmp/emergency_sae_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "has_unblinding_note": $HAS_UNBLINDING,
    "has_sae_note": $HAS_SAE,
    "event_scheduled": $EVENT_SCHEDULED,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

rm -f /tmp/emergency_sae_result.json 2>/dev/null || sudo rm -f /tmp/emergency_sae_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/emergency_sae_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/emergency_sae_result.json
chmod 666 /tmp/emergency_sae_result.json 2>/dev/null || sudo chmod 666 /tmp/emergency_sae_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete"