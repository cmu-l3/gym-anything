#!/bin/bash
echo "=== Exporting site_operations result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual evidence
take_screenshot /tmp/task_end_screenshot.png

# Resolve IDs
CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' AND parent_study_id = $CV_STUDY_ID AND status_id != 3 LIMIT 1")

if [ -z "$SITE_ID" ]; then
    echo "ERROR: Site not found."
    SITE_ID="-1"
fi
echo "Parent ID: $CV_STUDY_ID, Site ID: $SITE_ID"

# Initialize variables
CV201_ENROLLED_SITE="false"
CV201_ENROLLED_PARENT="false"
CV201_GENDER=""
CV201_DOB=""
CV201_EVENT_FOUND="false"
CV201_EVENT_DATE=""

CV202_ENROLLED_SITE="false"
CV202_ENROLLED_PARENT="false"
CV202_GENDER=""
CV202_DOB=""
CV202_EVENT_FOUND="false"
CV202_EVENT_DATE=""

MRIVERA_SITE_ROLE_EXISTS="false"
MRIVERA_SITE_ROLE_NAME=""

# Function to check subject enrollment and events
check_subject() {
    local label=$1
    local var_prefix=$2
    
    # 1. Check Site Enrollment
    local SITE_DATA=$(oc_query "SELECT ss.study_subject_id, sub.gender, sub.date_of_birth FROM study_subject ss JOIN subject sub ON ss.subject_id = sub.subject_id WHERE ss.label = '$label' AND ss.study_id = $SITE_ID AND ss.status_id != 3 LIMIT 1")
    
    # 2. Check Parent Enrollment (if not at site)
    local PARENT_DATA=""
    if [ -z "$SITE_DATA" ]; then
        PARENT_DATA=$(oc_query "SELECT ss.study_subject_id, sub.gender, sub.date_of_birth FROM study_subject ss JOIN subject sub ON ss.subject_id = sub.subject_id WHERE ss.label = '$label' AND ss.study_id = $CV_STUDY_ID AND ss.status_id != 3 LIMIT 1")
    fi
    
    local ACTIVE_SS_ID=""
    
    if [ -n "$SITE_DATA" ]; then
        eval "${var_prefix}_ENROLLED_SITE='true'"
        ACTIVE_SS_ID=$(echo "$SITE_DATA" | cut -d'|' -f1)
        eval "${var_prefix}_GENDER='$(echo "$SITE_DATA" | cut -d'|' -f2)'"
        eval "${var_prefix}_DOB='$(echo "$SITE_DATA" | cut -d'|' -f3)'"
    elif [ -n "$PARENT_DATA" ]; then
        eval "${var_prefix}_ENROLLED_PARENT='true'"
        ACTIVE_SS_ID=$(echo "$PARENT_DATA" | cut -d'|' -f1)
        eval "${var_prefix}_GENDER='$(echo "$PARENT_DATA" | cut -d'|' -f2)'"
        eval "${var_prefix}_DOB='$(echo "$PARENT_DATA" | cut -d'|' -f3)'"
    fi
    
    # Check Event if Subject was found
    if [ -n "$ACTIVE_SS_ID" ]; then
        local EVENT_DATA=$(oc_query "SELECT se.date_start FROM study_event se JOIN study_event_definition sed ON se.study_event_definition_id = sed.study_event_definition_id WHERE se.study_subject_id = $ACTIVE_SS_ID AND sed.name = 'Screening Visit' LIMIT 1")
        if [ -n "$EVENT_DATA" ]; then
            eval "${var_prefix}_EVENT_FOUND='true'"
            eval "${var_prefix}_EVENT_DATE='$(echo "$EVENT_DATA" | cut -d'|' -f1)'"
        fi
    fi
}

# Check CV-201
check_subject "CV-201" "CV201"
# Check CV-202
check_subject "CV-202" "CV202"

# Check mrivera site role
ROLE_DATA=$(oc_query "SELECT role_name FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $SITE_ID AND status_id != 3 LIMIT 1")
if [ -n "$ROLE_DATA" ]; then
    MRIVERA_SITE_ROLE_EXISTS="true"
    MRIVERA_SITE_ROLE_NAME="$ROLE_DATA"
fi

# Audit logs
AUDIT_BASELINE=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
AUDIT_CURRENT=$(get_recent_audit_count 60)
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write Results
TEMP_JSON=$(mktemp /tmp/site_operations_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cv201_enrolled_site": $CV201_ENROLLED_SITE,
    "cv201_enrolled_parent": $CV201_ENROLLED_PARENT,
    "cv201_gender": "$(json_escape "${CV201_GENDER:-}")",
    "cv201_dob": "$(json_escape "${CV201_DOB:-}")",
    "cv201_event_found": $CV201_EVENT_FOUND,
    "cv201_event_date": "$(json_escape "${CV201_EVENT_DATE:-}")",
    
    "cv202_enrolled_site": $CV202_ENROLLED_SITE,
    "cv202_enrolled_parent": $CV202_ENROLLED_PARENT,
    "cv202_gender": "$(json_escape "${CV202_GENDER:-}")",
    "cv202_dob": "$(json_escape "${CV202_DOB:-}")",
    "cv202_event_found": $CV202_EVENT_FOUND,
    "cv202_event_date": "$(json_escape "${CV202_EVENT_DATE:-}")",
    
    "mrivera_site_role_exists": $MRIVERA_SITE_ROLE_EXISTS,
    "mrivera_site_role_name": "$(json_escape "${MRIVERA_SITE_ROLE_NAME:-}")",
    
    "audit_baseline": ${AUDIT_BASELINE:-0},
    "audit_current": ${AUDIT_CURRENT:-0},
    "result_nonce": "$(json_escape "$NONCE")",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move and fix permissions
rm -f /tmp/site_operations_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/site_operations_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/site_operations_result.json
chmod 666 /tmp/site_operations_result.json 2>/dev/null || sudo chmod 666 /tmp/site_operations_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/site_operations_result.json