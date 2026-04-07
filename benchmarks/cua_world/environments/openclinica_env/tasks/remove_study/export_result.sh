#!/bin/bash
echo "=== Exporting remove_study result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

# 1. Fetch current statuses from the database
CV_STATUS=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1" 2>/dev/null || echo "0")
DM_STATUS=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1" 2>/dev/null || echo "0")
AP_STATUS=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' LIMIT 1" 2>/dev/null || echo "0")

# 2. Check for UI interaction via audit logs
CURRENT_AUDIT_COUNT=$(oc_query "SELECT COUNT(*) FROM audit_event" 2>/dev/null || echo "0")

# 3. Load baselines
BASELINE_CV=$(cat /tmp/baseline_cv_status.txt 2>/dev/null || echo "1")
BASELINE_DM=$(cat /tmp/baseline_dm_status.txt 2>/dev/null || echo "1")
BASELINE_AP=$(cat /tmp/baseline_ap_status.txt 2>/dev/null || echo "4")
BASELINE_AUDIT_COUNT=$(cat /tmp/baseline_audit_count.txt 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# 4. Check if the specific removal audit event exists for the Cardiovascular Registry
# A soft deletion usually creates an audit_event with action_message like '%Status Changed%'
AUDIT_TARGET_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1" 2>/dev/null || echo "0")
REMOVAL_AUDIT_EXISTS=$(oc_query "SELECT COUNT(*) FROM audit_event WHERE audit_table = 'study' AND entity_id = ${AUDIT_TARGET_ID} AND action_message LIKE '%Status%' AND audit_id > (SELECT MAX(audit_id) - 1000 FROM audit_event)" 2>/dev/null || echo "0")

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/remove_study_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_study": "CV-REG-2023",
    "baseline_cv_status": ${BASELINE_CV:-1},
    "current_cv_status": ${CV_STATUS:-0},
    "baseline_dm_status": ${BASELINE_DM:-1},
    "current_dm_status": ${DM_STATUS:-0},
    "baseline_ap_status": ${BASELINE_AP:-4},
    "current_ap_status": ${AP_STATUS:-0},
    "baseline_audit_count": ${BASELINE_AUDIT_COUNT:-0},
    "current_audit_count": ${CURRENT_AUDIT_COUNT:-0},
    "removal_audit_count": ${REMOVAL_AUDIT_EXISTS:-0},
    "result_nonce": "${NONCE}"
}
EOF

# Move to standard location securely
rm -f /tmp/remove_study_result.json 2>/dev/null || sudo rm -f /tmp/remove_study_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/remove_study_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/remove_study_result.json
chmod 666 /tmp/remove_study_result.json 2>/dev/null || sudo chmod 666 /tmp/remove_study_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/remove_study_result.json"
cat /tmp/remove_study_result.json
echo "=== Export complete ==="