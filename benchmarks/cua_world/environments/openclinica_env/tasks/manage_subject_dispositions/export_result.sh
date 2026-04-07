#!/bin/bash
echo "=== Exporting manage_subject_dispositions result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Resolve study_id for DM-TRIAL-2024
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")

# 2. Query statuses for all five subjects
declare -A STATUSES

SUBJECTS=("DM-101" "DM-102" "DM-103" "DM-104" "DM-105")
for label in "${SUBJECTS[@]}"; do
    STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE label = '$label' AND study_id = $DM_STUDY_ID LIMIT 1")
    STATUSES["$label"]=${STATUS:-0}
    echo "$label status_id: ${STATUSES["$label"]}"
done

# 3. Get audit log count
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit log count: $AUDIT_LOG_COUNT (baseline: $AUDIT_BASELINE_COUNT)"

# 4. Read nonce
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# 5. Write results to JSON
TEMP_JSON=$(mktemp /tmp/manage_subject_dispositions.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "statuses": {
        "DM-101": ${STATUSES["DM-101"]},
        "DM-102": ${STATUSES["DM-102"]},
        "DM-103": ${STATUSES["DM-103"]},
        "DM-104": ${STATUSES["DM-104"]},
        "DM-105": ${STATUSES["DM-105"]}
    },
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

# Move temp file to final location safely
rm -f /tmp/manage_subject_dispositions_result.json 2>/dev/null || sudo rm -f /tmp/manage_subject_dispositions_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/manage_subject_dispositions_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/manage_subject_dispositions_result.json
chmod 666 /tmp/manage_subject_dispositions_result.json 2>/dev/null || sudo chmod 666 /tmp/manage_subject_dispositions_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/manage_subject_dispositions_result.json"
cat /tmp/manage_subject_dispositions_result.json

echo "=== Export complete ==="