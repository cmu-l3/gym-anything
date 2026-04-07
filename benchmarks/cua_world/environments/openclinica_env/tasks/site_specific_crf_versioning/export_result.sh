#!/bin/bash
echo "=== Exporting site_specific_crf_versioning result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load IDs
DM_ID=$(jq -r '.dm_id' /tmp/task_ids.json)
SITE_ID=$(jq -r '.site_id' /tmp/task_ids.json)
SED_ID=$(jq -r '.sed_id' /tmp/task_ids.json)
CRF_ID=$(jq -r '.crf_id' /tmp/task_ids.json)
V1_ID=$(jq -r '.v1_id' /tmp/task_ids.json)
V2_ID=$(jq -r '.v2_id' /tmp/task_ids.json)

# Check Parent Level Default Version
PARENT_V_ID=$(oc_query "SELECT default_version_id FROM event_definition_crf WHERE study_event_definition_id=$SED_ID AND study_id=$DM_ID AND crf_id=$CRF_ID AND status_id != 3 LIMIT 1")

# Check Site Level Override Version
# Note: If no row exists, the query returns empty string, which is correct (it implies it inherits parent v1.0)
SITE_V_ID=$(oc_query "SELECT default_version_id FROM event_definition_crf WHERE study_event_definition_id=$SED_ID AND study_id=$SITE_ID AND crf_id=$CRF_ID AND status_id != 3 LIMIT 1")

# Audit check
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/crf_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "v1_id": "${V1_ID}",
    "v2_id": "${V2_ID}",
    "parent_v_id": "${PARENT_V_ID}",
    "site_v_id": "${SITE_V_ID}",
    "audit_baseline": ${AUDIT_BASELINE_COUNT},
    "audit_current": ${AUDIT_LOG_COUNT},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')"
}
EOF

# Ensure file is readable
rm -f /tmp/site_crf_result.json 2>/dev/null || sudo rm -f /tmp/site_crf_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/site_crf_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/site_crf_result.json
chmod 666 /tmp/site_crf_result.json 2>/dev/null || sudo chmod 666 /tmp/site_crf_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export completed. Results stored in /tmp/site_crf_result.json"
cat /tmp/site_crf_result.json