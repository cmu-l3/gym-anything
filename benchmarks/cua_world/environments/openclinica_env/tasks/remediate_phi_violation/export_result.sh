#!/bin/bash
echo "=== Exporting remediate_phi_violation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# --- Fetch Site Information ---
SITE_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-BHI-001' AND status_id != 3 LIMIT 1")
FACILITY_NAME=""
if [ -n "$SITE_ID" ]; then
    FACILITY_NAME=$(oc_query "SELECT facility_name FROM study WHERE study_id = $SITE_ID LIMIT 1")
fi
echo "Facility Name: $FACILITY_NAME"

# --- Check remaining PHI ---
MRN_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE label LIKE 'MRN-%' AND study_id = $SITE_ID AND status_id != 3")
PHI_NAMES_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE (secondary_label LIKE '%John Doe%' OR secondary_label LIKE '%Mary Smith%' OR secondary_label LIKE '%Robert Jones%') AND study_id = $SITE_ID AND status_id != 3")

echo "Remaining MRNs: ${MRN_COUNT:-0}"
echo "Remaining PHI Names: ${PHI_NAMES_COUNT:-0}"

# --- Check Remediated Subjects ---
check_subject() {
    local target_id=$1
    local found="false"
    local sec_cleared="false"
    local sec_val=""

    local query_res=$(oc_query "SELECT secondary_label FROM study_subject WHERE label = '$target_id' AND study_id = $SITE_ID AND status_id != 3 LIMIT 1")
    
    # If exit code was 0 and we got *some* response (even empty string if it was null/empty)
    if [ $? -eq 0 ] && [ "$query_res" != "DB_ERROR" ]; then
        # Check if the row actually exists by getting ID first to be safe
        local exists=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = '$target_id' AND study_id = $SITE_ID AND status_id != 3 LIMIT 1")
        if [ -n "$exists" ]; then
            found="true"
            sec_val="$query_res"
            # In PostgreSQL, an empty secondary label might be returned as empty string or completely blank
            if [ -z "$sec_val" ] || [ "$sec_val" = " " ]; then
                sec_cleared="true"
            fi
        fi
    fi
    
    echo "{\"found\": $found, \"sec_cleared\": $sec_cleared, \"sec_val\": \"$(json_escape "$sec_val")\"}"
}

CV301_JSON=$(check_subject "CV-301")
CV302_JSON=$(check_subject "CV-302")
CV303_JSON=$(check_subject "CV-303")

# --- Anti-Gaming Audit Check ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# --- Export JSON ---
TEMP_JSON=$(mktemp /tmp/phi_remediation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "site_id": "${SITE_ID:-}",
    "facility_name": "$(json_escape "$FACILITY_NAME")",
    "mrn_count": ${MRN_COUNT:-0},
    "phi_names_count": ${PHI_NAMES_COUNT:-0},
    "cv301": $CV301_JSON,
    "cv302": $CV302_JSON,
    "cv303": $CV303_JSON,
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")"
}
EOF

# Move securely
rm -f /tmp/phi_remediation_result.json 2>/dev/null || sudo rm -f /tmp/phi_remediation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/phi_remediation_result.json
chmod 666 /tmp/phi_remediation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/phi_remediation_result.json