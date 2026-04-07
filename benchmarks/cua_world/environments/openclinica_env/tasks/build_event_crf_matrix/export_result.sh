#!/bin/bash
echo "=== Exporting build_event_crf_matrix result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

# Helper function to check specific assignments
check_assignment() {
    local event_name="$1"
    local crf_name="$2"
    local res=$(oc_query "
        SELECT edc.required_crf 
        FROM event_definition_crf edc 
        JOIN study_event_definition sed ON edc.study_event_definition_id = sed.study_event_definition_id 
        JOIN crf c ON edc.crf_id = c.crf_id 
        WHERE sed.name = '$event_name' 
          AND c.name = '$crf_name' 
          AND sed.study_id = $DM_STUDY_ID 
          AND edc.status_id != 3 
        LIMIT 1
    ")
    
    if [ -n "$res" ]; then
        echo "true|$(echo "$res" | grep -qi "t\|true\|1" && echo "true" || echo "false")"
    else
        echo "false|false"
    fi
}

# Evaluate the 6 expected assignments
DEMO_SCREENING=$(check_assignment "Screening Visit" "Demographics")
VITAL_SCREENING=$(check_assignment "Screening Visit" "Vital Signs")
VITAL_BASELINE=$(check_assignment "Baseline Visit" "Vital Signs")
LAB_BASELINE=$(check_assignment "Baseline Visit" "Lab Results")
VITAL_WEEK12=$(check_assignment "Week 12 Final Visit" "Vital Signs")
LAB_WEEK12=$(check_assignment "Week 12 Final Visit" "Lab Results")

# Audit log info
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write to JSON
TEMP_JSON=$(mktemp /tmp/matrix_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "result_nonce": "$NONCE",
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "assignments": {
        "demo_screening_exists": $(echo "$DEMO_SCREENING" | cut -d'|' -f1),
        "demo_screening_required": $(echo "$DEMO_SCREENING" | cut -d'|' -f2),
        "vital_screening_exists": $(echo "$VITAL_SCREENING" | cut -d'|' -f1),
        "vital_screening_required": $(echo "$VITAL_SCREENING" | cut -d'|' -f2),
        "vital_baseline_exists": $(echo "$VITAL_BASELINE" | cut -d'|' -f1),
        "vital_baseline_required": $(echo "$VITAL_BASELINE" | cut -d'|' -f2),
        "lab_baseline_exists": $(echo "$LAB_BASELINE" | cut -d'|' -f1),
        "lab_baseline_required": $(echo "$LAB_BASELINE" | cut -d'|' -f2),
        "vital_week12_exists": $(echo "$VITAL_WEEK12" | cut -d'|' -f1),
        "vital_week12_required": $(echo "$VITAL_WEEK12" | cut -d'|' -f2),
        "lab_week12_exists": $(echo "$LAB_WEEK12" | cut -d'|' -f1),
        "lab_week12_required": $(echo "$LAB_WEEK12" | cut -d'|' -f2)
    }
}
EOF

# Move securely
rm -f /tmp/build_event_crf_matrix_result.json 2>/dev/null || sudo rm -f /tmp/build_event_crf_matrix_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/build_event_crf_matrix_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/build_event_crf_matrix_result.json
chmod 666 /tmp/build_event_crf_matrix_result.json 2>/dev/null || sudo chmod 666 /tmp/build_event_crf_matrix_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Assignments payload:"
cat /tmp/build_event_crf_matrix_result.json