#!/bin/bash
echo "=== Exporting crf_data_correction_workflow result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Retrieve current values directly from DB by joining through the hierarchy
DM101_SYSBP=$(oc_query "
    SELECT id.value FROM item_data id
    JOIN item i ON id.item_id = i.item_id
    JOIN event_crf ec ON id.event_crf_id = ec.event_crf_id
    JOIN study_event se ON ec.study_event_id = se.study_event_id
    JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id
    WHERE ss.label = 'DM-101' AND i.name = 'SYSBP'
    ORDER BY id.item_data_id DESC LIMIT 1
")

DM102_HR=$(oc_query "
    SELECT id.value FROM item_data id
    JOIN item i ON id.item_id = i.item_id
    JOIN event_crf ec ON id.event_crf_id = ec.event_crf_id
    JOIN study_event se ON ec.study_event_id = se.study_event_id
    JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id
    WHERE ss.label = 'DM-102' AND i.name = 'HR'
    ORDER BY id.item_data_id DESC LIMIT 1
")

echo "Current DM-101 SYSBP: $DM101_SYSBP"
echo "Current DM-102 HR: $DM102_HR"

# Audit Log analysis
AUDIT_RFC_BASELINE=$(cat /tmp/audit_rfc_baseline 2>/dev/null || echo "0")
AUDIT_RFC_CURRENT=$(oc_query "SELECT COUNT(*) FROM audit_event WHERE reason_for_change IS NOT NULL")
RFC_EVENTS_CREATED=$(( AUDIT_RFC_CURRENT - AUDIT_RFC_BASELINE ))

GENERAL_AUDIT_COUNT=$(get_recent_audit_count 60)

echo "RFC Baseline: $AUDIT_RFC_BASELINE, Current: $AUDIT_RFC_CURRENT (Added: $RFC_EVENTS_CREATED)"
echo "General recent audit events: $GENERAL_AUDIT_COUNT"

NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write output to JSON
TEMP_JSON=$(mktemp /tmp/crf_correction_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm101_sysbp_value": "$(json_escape "${DM101_SYSBP:-}")",
    "dm102_hr_value": "$(json_escape "${DM102_HR:-}")",
    "rfc_events_created": ${RFC_EVENTS_CREATED:-0},
    "general_audit_count": ${GENERAL_AUDIT_COUNT:-0},
    "result_nonce": "$NONCE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/crf_correction_result.json 2>/dev/null || sudo rm -f /tmp/crf_correction_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crf_correction_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/crf_correction_result.json
chmod 666 /tmp/crf_correction_result.json 2>/dev/null || sudo chmod 666 /tmp/crf_correction_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/crf_correction_result.json"
echo "=== Export Complete ==="