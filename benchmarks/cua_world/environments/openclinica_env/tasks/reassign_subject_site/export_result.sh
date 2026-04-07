#!/bin/bash
echo "=== Exporting reassign_subject_site result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Fetch IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-BOS-001' AND status_id != 3 LIMIT 1")

# Check BOS-101
BOS101_DATA=$(oc_query "SELECT study_id FROM study_subject WHERE label = 'BOS-101' AND status_id != 3 LIMIT 1")
BOS101_EXISTS="false"
BOS101_STUDY_ID="0"

if [ -n "$BOS101_DATA" ]; then
    BOS101_EXISTS="true"
    BOS101_STUDY_ID="$BOS101_DATA"
fi

# Check DM-101
DM101_EXISTS="false"
DM101_DATA=$(oc_query "SELECT study_id FROM study_subject WHERE label = 'DM-101' AND status_id != 3 LIMIT 1")
if [ -n "$DM101_DATA" ]; then
    DM101_EXISTS="true"
fi

# Audit Log Check
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

TEMP_JSON=$(mktemp /tmp/reassign_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "parent_study_id": ${DM_STUDY_ID:-0},
    "site_study_id": ${SITE_ID:-0},
    "bos101_exists": $BOS101_EXISTS,
    "bos101_study_id": ${BOS101_STUDY_ID:-0},
    "dm101_exists": $DM101_EXISTS,
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "result_nonce": "$NONCE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move securely
rm -f /tmp/reassign_subject_site_result.json 2>/dev/null || sudo rm -f /tmp/reassign_subject_site_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/reassign_subject_site_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/reassign_subject_site_result.json
chmod 666 /tmp/reassign_subject_site_result.json 2>/dev/null || sudo chmod 666 /tmp/reassign_subject_site_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete: /tmp/reassign_subject_site_result.json"
cat /tmp/reassign_subject_site_result.json