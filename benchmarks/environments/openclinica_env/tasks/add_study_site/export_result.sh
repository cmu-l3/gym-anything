#!/bin/bash
echo "=== Exporting add_study_site result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
echo "CV Registry study_id: $CV_STUDY_ID"

INITIAL_SITE_COUNT=$(cat /tmp/initial_site_count 2>/dev/null || echo "0")
INITIAL_SUBJECT_COUNT=$(cat /tmp/initial_cv_subject_count 2>/dev/null || echo "0")

# --- Check for Boston Heart Institute site ---
SITE_DATA=$(oc_query "SELECT study_id, name, unique_identifier, principal_investigator FROM study WHERE parent_study_id = $CV_STUDY_ID AND status_id != 3 ORDER BY study_id DESC LIMIT 1")
SITE_FOUND="false"
SITE_ID=""
SITE_NAME=""
SITE_PROTOCOL_ID=""
SITE_PI=""
SITE_PROTOCOL_ID_CORRECT="false"

if [ -n "$SITE_DATA" ]; then
    SITE_FOUND="true"
    SITE_ID=$(echo "$SITE_DATA" | cut -d'|' -f1)
    SITE_NAME=$(echo "$SITE_DATA" | cut -d'|' -f2)
    SITE_PROTOCOL_ID=$(echo "$SITE_DATA" | cut -d'|' -f3)
    SITE_PI=$(echo "$SITE_DATA" | cut -d'|' -f4)
    if echo "$SITE_PROTOCOL_ID" | grep -qi "CV-BHI-001\|CVBHI001"; then
        SITE_PROTOCOL_ID_CORRECT="true"
    fi
fi
echo "Site: found=$SITE_FOUND, name='$SITE_NAME', id='$SITE_PROTOCOL_ID', pi='$SITE_PI'"

# --- Check CV-101 enrollment (at parent study level) ---
CV101_DATA=$(oc_query "SELECT ss.study_subject_id, ss.label, ss.study_id, sb.gender, sb.date_of_birth FROM study_subject ss JOIN subject sb ON ss.subject_id = sb.subject_id WHERE ss.label = 'CV-101' AND ss.study_id = $CV_STUDY_ID AND ss.status_id != 3 LIMIT 1")
CV101_FOUND="false"
CV101_GENDER=""
CV101_DOB=""
CV101_GENDER_CORRECT="false"
CV101_DOB_CORRECT="false"

if [ -n "$CV101_DATA" ]; then
    CV101_FOUND="true"
    CV101_GENDER=$(echo "$CV101_DATA" | cut -d'|' -f4)
    CV101_DOB=$(echo "$CV101_DATA" | cut -d'|' -f5)
    if echo "$CV101_GENDER" | grep -qi "^m"; then
        CV101_GENDER_CORRECT="true"
    fi
    if echo "$CV101_DOB" | grep -q "1952-03-18\|1952"; then
        CV101_DOB_CORRECT="true"
    fi
fi
echo "CV-101: found=$CV101_FOUND, gender=$CV101_GENDER, dob=$CV101_DOB"

# --- Check CV-102 enrollment (at site level OR parent level — accept both) ---
CV102_FOUND="false"
CV102_AT_SITE="false"
CV102_GENDER=""
CV102_DOB=""
CV102_GENDER_CORRECT="false"
CV102_DOB_CORRECT="false"

# Try at site level first
if [ -n "$SITE_ID" ]; then
    CV102_DATA=$(oc_query "SELECT ss.study_subject_id, ss.label, ss.study_id, sb.gender, sb.date_of_birth FROM study_subject ss JOIN subject sb ON ss.subject_id = sb.subject_id WHERE ss.label = 'CV-102' AND ss.study_id = $SITE_ID AND ss.status_id != 3 LIMIT 1")
    if [ -n "$CV102_DATA" ]; then
        CV102_FOUND="true"
        CV102_AT_SITE="true"
        CV102_GENDER=$(echo "$CV102_DATA" | cut -d'|' -f4)
        CV102_DOB=$(echo "$CV102_DATA" | cut -d'|' -f5)
    fi
fi
# Also check at parent level (acceptable fallback)
if [ "$CV102_FOUND" = "false" ]; then
    CV102_DATA=$(oc_query "SELECT ss.study_subject_id, ss.label, ss.study_id, sb.gender, sb.date_of_birth FROM study_subject ss JOIN subject sb ON ss.subject_id = sb.subject_id WHERE ss.label = 'CV-102' AND ss.study_id = $CV_STUDY_ID AND ss.status_id != 3 LIMIT 1")
    if [ -n "$CV102_DATA" ]; then
        CV102_FOUND="true"
        CV102_AT_SITE="false"
        CV102_GENDER=$(echo "$CV102_DATA" | cut -d'|' -f4)
        CV102_DOB=$(echo "$CV102_DATA" | cut -d'|' -f5)
    fi
fi

if [ "$CV102_FOUND" = "true" ]; then
    if echo "$CV102_GENDER" | grep -qi "^f"; then
        CV102_GENDER_CORRECT="true"
    fi
    if echo "$CV102_DOB" | grep -q "1967-11-05\|1967"; then
        CV102_DOB_CORRECT="true"
    fi
fi
echo "CV-102: found=$CV102_FOUND, at_site=$CV102_AT_SITE, gender=$CV102_GENDER, dob=$CV102_DOB"

CURRENT_SITE_COUNT=$(oc_query "SELECT COUNT(*) FROM study WHERE parent_study_id = $CV_STUDY_ID AND status_id != 3")
CURRENT_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject ss JOIN study s ON ss.study_id = s.study_id WHERE (s.study_id = $CV_STUDY_ID OR s.parent_study_id = $CV_STUDY_ID) AND ss.status_id != 3")

AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/add_site_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_site_count": ${INITIAL_SITE_COUNT:-0},
    "current_site_count": ${CURRENT_SITE_COUNT:-0},
    "initial_subject_count": ${INITIAL_SUBJECT_COUNT:-0},
    "current_subject_count": ${CURRENT_SUBJECT_COUNT:-0},
    "site_found": $SITE_FOUND,
    "site_name": "$(json_escape "${SITE_NAME:-}")",
    "site_protocol_id": "$(json_escape "${SITE_PROTOCOL_ID:-}")",
    "site_pi": "$(json_escape "${SITE_PI:-}")",
    "site_protocol_id_correct": $SITE_PROTOCOL_ID_CORRECT,
    "cv101_found": $CV101_FOUND,
    "cv101_gender": "$(json_escape "${CV101_GENDER:-}")",
    "cv101_dob": "$(json_escape "${CV101_DOB:-}")",
    "cv101_gender_correct": $CV101_GENDER_CORRECT,
    "cv101_dob_correct": $CV101_DOB_CORRECT,
    "cv102_found": $CV102_FOUND,
    "cv102_at_site": $CV102_AT_SITE,
    "cv102_gender": "$(json_escape "${CV102_GENDER:-}")",
    "cv102_dob": "$(json_escape "${CV102_DOB:-}")",
    "cv102_gender_correct": $CV102_GENDER_CORRECT,
    "cv102_dob_correct": $CV102_DOB_CORRECT,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/add_study_site_result.json"

echo "=== Export complete ==="
