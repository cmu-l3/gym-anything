#!/bin/bash
echo "=== Exporting administrative_data_invalidation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# 1. DM-102 Pregnancy CRF status
DM102_PREG_STATUS=$(oc_query "SELECT ec.status_id FROM event_crf ec JOIN study_event se ON ec.study_event_id = se.study_event_id JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id JOIN crf c ON cv.crf_id = c.crf_id WHERE ss.label = 'DM-102' AND c.name = 'Pregnancy Status' LIMIT 1")

# 2. DM-102 Vitals CRF status (Collateral check)
DM102_VITAL_STATUS=$(oc_query "SELECT ec.status_id FROM event_crf ec JOIN study_event se ON ec.study_event_id = se.study_event_id JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id JOIN crf c ON cv.crf_id = c.crf_id WHERE ss.label = 'DM-102' AND c.name = 'Vital Signs' LIMIT 1")

# 3. DM-104 Week 8 Event status
DM104_WEEK8_STATUS=$(oc_query "SELECT se.status_id FROM study_event se JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id JOIN study_event_definition sed ON se.study_event_definition_id = sed.study_event_definition_id WHERE ss.label = 'DM-104' AND sed.name = 'Week 8 Follow-up' LIMIT 1")

# 4. DM-101 Vitals CRF status
DM101_VITAL_STATUS=$(oc_query "SELECT ec.status_id FROM event_crf ec JOIN study_event se ON ec.study_event_id = se.study_event_id JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id JOIN crf c ON cv.crf_id = c.crf_id WHERE ss.label = 'DM-101' AND c.name = 'Vital Signs' LIMIT 1")

# Auditing & Integrity
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
RESULT_NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm102_preg_status": ${DM102_PREG_STATUS:--1},
    "dm102_vital_status": ${DM102_VITAL_STATUS:--1},
    "dm104_week8_status": ${DM104_WEEK8_STATUS:--1},
    "dm101_vital_status": ${DM101_VITAL_STATUS:--1},
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(json_escape "$RESULT_NONCE")"
}
EOF

# Move payload with fallback permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="