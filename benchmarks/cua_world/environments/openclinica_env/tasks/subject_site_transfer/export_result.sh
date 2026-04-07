#!/bin/bash
echo "=== Exporting subject_site_transfer result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Retrieve IDs
BOS_ID=$(cat /tmp/bos_site_id 2>/dev/null)
NY_ID=$(cat /tmp/ny_site_id 2>/dev/null)

# 1. Look up DM-105's current study assignment
# If reassigned, OpenClinica updates the study_id for the study_subject row
DM105_DATA=$(oc_query "SELECT study_id, status_id FROM study_subject WHERE label = 'DM-105' AND status_id != 3 ORDER BY study_subject_id DESC LIMIT 1" 2>/dev/null || echo "")
DM105_STUDY_ID=$(echo "$DM105_DATA" | cut -d'|' -f1)
DM105_STATUS=$(echo "$DM105_DATA" | cut -d'|' -f2)

echo "DM-105 current study_id: $DM105_STUDY_ID (Status: $DM105_STATUS)"

# 2. Look up DM-105's current demographics
DM105_DEMO=$(oc_query "SELECT s.gender, s.date_of_birth FROM subject s JOIN study_subject ss ON s.subject_id = ss.subject_id WHERE ss.label = 'DM-105' AND ss.status_id != 3 ORDER BY ss.study_subject_id DESC LIMIT 1" 2>/dev/null || echo "")
DM105_GENDER=$(echo "$DM105_DEMO" | cut -d'|' -f1)
DM105_DOB=$(echo "$DM105_DEMO" | cut -d'|' -f2)

echo "DM-105 current demographics -> Gender: $DM105_GENDER, DOB: $DM105_DOB"

# 3. Check for GUI interaction (Audit logs)
AUDIT_BASELINE=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
AUDIT_CURRENT=$(oc_query "SELECT COUNT(*) FROM audit_log_event" 2>/dev/null || echo "$AUDIT_BASELINE")
AUDIT_DIFF=$((AUDIT_CURRENT - AUDIT_BASELINE))

echo "Audit log activity -> Baseline: $AUDIT_BASELINE, Current: $AUDIT_CURRENT (Diff: $AUDIT_DIFF)"

# 4. Write results to JSON
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

TEMP_JSON=$(mktemp /tmp/subject_site_transfer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "bos_site_id": "${BOS_ID:-0}",
    "ny_site_id": "${NY_ID:-0}",
    "dm105_study_id": "${DM105_STUDY_ID:-0}",
    "dm105_status": "${DM105_STATUS:-0}",
    "dm105_gender": "$(json_escape "${DM105_GENDER:-}")",
    "dm105_dob": "$(json_escape "${DM105_DOB:-}")",
    "audit_diff": ${AUDIT_DIFF:-0},
    "result_nonce": "$NONCE"
}
EOF

# Move securely
rm -f /tmp/subject_site_transfer_result.json 2>/dev/null || sudo rm -f /tmp/subject_site_transfer_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/subject_site_transfer_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/subject_site_transfer_result.json
chmod 666 /tmp/subject_site_transfer_result.json 2>/dev/null || sudo chmod 666 /tmp/subject_site_transfer_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/subject_site_transfer_result.json"
cat /tmp/subject_site_transfer_result.json

echo "=== Export Complete ==="