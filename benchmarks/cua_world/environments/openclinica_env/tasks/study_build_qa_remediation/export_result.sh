#!/bin/bash
echo "=== Exporting study_build_qa_remediation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Resolve Study ID
ONC_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'ONC-2025' LIMIT 1")
echo "ONC-2025 study_id: $ONC_STUDY_ID"

if [ -z "$ONC_STUDY_ID" ]; then
    echo "ERROR: ONC-2025 study not found."
    exit 0
fi

# 1. Check Study Phase
STUDY_PHASE=$(oc_query "SELECT phase FROM study WHERE study_id = $ONC_STUDY_ID")
echo "Study Phase: $STUDY_PHASE"

# 2. Check Baseline repeating flag
BASELINE_REP=$(oc_query "SELECT repeating::text FROM study_event_definition WHERE study_id = $ONC_STUDY_ID AND name = 'Baseline Visit'")
echo "Baseline repeating: $BASELINE_REP"

# 3. Check AE Report type
AE_TYPE=$(oc_query "SELECT type FROM study_event_definition WHERE study_id = $ONC_STUDY_ID AND name = 'Adverse Event Report'")
echo "AE Type: $AE_TYPE"

# 4A. Check Demographics on Week 8 Follow-up (should be missing or status_id != 1)
WK8_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$ONC_STUDY_ID AND name='Week 8 Follow-up' LIMIT 1")
DEMO_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name='Demographics' LIMIT 1")
DEMO_WK8_STATUS="0"
if [ -n "$WK8_SED_ID" ] && [ -n "$DEMO_CRF_ID" ]; then
    DEMO_WK8_STATUS=$(oc_query "SELECT status_id FROM event_definition_crf WHERE study_event_definition_id = $WK8_SED_ID AND crf_id = $DEMO_CRF_ID ORDER BY event_definition_crf_id DESC LIMIT 1" 2>/dev/null)
fi
if [ -z "$DEMO_WK8_STATUS" ]; then DEMO_WK8_STATUS="0"; fi
echo "Demographics on Week 8 status: $DEMO_WK8_STATUS"

# 4B. Check Vital Signs on Screening Visit (should be status_id == 1)
SCR_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE study_id=$ONC_STUDY_ID AND name='Screening Visit' LIMIT 1")
VITALS_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE name='Vital Signs' LIMIT 1")
VITALS_SCR_STATUS="0"
if [ -n "$SCR_SED_ID" ] && [ -n "$VITALS_CRF_ID" ]; then
    VITALS_SCR_STATUS=$(oc_query "SELECT status_id FROM event_definition_crf WHERE study_event_definition_id = $SCR_SED_ID AND crf_id = $VITALS_CRF_ID ORDER BY event_definition_crf_id DESC LIMIT 1" 2>/dev/null)
fi
if [ -z "$VITALS_SCR_STATUS" ]; then VITALS_SCR_STATUS="0"; fi
echo "Vital Signs on Screening status: $VITALS_SCR_STATUS"

# Get audit log counts
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write JSON
TEMP_JSON=$(mktemp /tmp/qa_remediation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "study_phase": "$(json_escape "${STUDY_PHASE:-}")",
    "baseline_repeating": "$(json_escape "${BASELINE_REP:-}")",
    "ae_type": "$(json_escape "${AE_TYPE:-}")",
    "demo_wk8_status": ${DEMO_WK8_STATUS:-0},
    "vitals_scr_status": ${VITALS_SCR_STATUS:-0},
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final destination
rm -f /tmp/qa_remediation_result.json 2>/dev/null || sudo rm -f /tmp/qa_remediation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/qa_remediation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/qa_remediation_result.json
chmod 666 /tmp/qa_remediation_result.json 2>/dev/null || sudo chmod 666 /tmp/qa_remediation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON exported:"
cat /tmp/qa_remediation_result.json
echo ""
echo "=== Export complete ==="