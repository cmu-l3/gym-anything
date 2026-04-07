#!/bin/bash
echo "=== Exporting correct_subject_demographics result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Resolve DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

get_subject_data() {
    local label=$1
    local data
    data=$(oc_query "SELECT s.gender, s.date_of_birth FROM subject s JOIN study_subject ss ON s.subject_id = ss.subject_id WHERE ss.label = '$label' AND ss.study_id = $DM_STUDY_ID LIMIT 1")
    echo "$data"
}

# 2. Extract current demographics
DM101_DATA=$(get_subject_data "DM-101")
DM101_GENDER=$(echo "$DM101_DATA" | cut -d'|' -f1)
DM101_DOB=$(echo "$DM101_DATA" | cut -d'|' -f2)

DM102_DATA=$(get_subject_data "DM-102")
DM102_GENDER=$(echo "$DM102_DATA" | cut -d'|' -f1)
DM102_DOB=$(echo "$DM102_DATA" | cut -d'|' -f2)

DM103_DATA=$(get_subject_data "DM-103")
DM103_GENDER=$(echo "$DM103_DATA" | cut -d'|' -f1)
DM103_DOB=$(echo "$DM103_DATA" | cut -d'|' -f2)

# 3. Extract current "other subjects" checksum
OTHER_SUBJ_CHECKSUM=$(oc_query "SELECT COUNT(*) || '-' || SUM(ASCII(gender)) || '-' || SUM(EXTRACT(EPOCH FROM date_of_birth)) FROM subject s JOIN study_subject ss ON s.subject_id = ss.subject_id WHERE ss.study_id = $DM_STUDY_ID AND ss.label NOT IN ('DM-101', 'DM-102', 'DM-103')" 2>/dev/null)
BASELINE_OTHER_SUBJ_CHECKSUM=$(cat /tmp/baseline_other_subj_checksum 2>/dev/null || echo "0")

# 4. Check Audit logs
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# 5. Write to JSON
TEMP_JSON=$(mktemp /tmp/correct_demographics_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm101": {
        "gender": "$(json_escape "${DM101_GENDER:-}")",
        "dob": "$(json_escape "${DM101_DOB:-}")"
    },
    "dm102": {
        "gender": "$(json_escape "${DM102_GENDER:-}")",
        "dob": "$(json_escape "${DM102_DOB:-}")"
    },
    "dm103": {
        "gender": "$(json_escape "${DM103_GENDER:-}")",
        "dob": "$(json_escape "${DM103_DOB:-}")"
    },
    "other_subj_checksum_initial": "$(json_escape "${BASELINE_OTHER_SUBJ_CHECKSUM:-}")",
    "other_subj_checksum_final": "$(json_escape "${OTHER_SUBJ_CHECKSUM:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")"
}
EOF

# Move securely
rm -f /tmp/correct_demographics_result.json 2>/dev/null || sudo rm -f /tmp/correct_demographics_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/correct_demographics_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/correct_demographics_result.json
chmod 666 /tmp/correct_demographics_result.json 2>/dev/null || sudo chmod 666 /tmp/correct_demographics_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/correct_demographics_result.json"
cat /tmp/correct_demographics_result.json
echo "=== Export complete ==="