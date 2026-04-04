#!/bin/bash
echo "=== Exporting crf_assignment_and_entry result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Get the DM Trial study_id
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
echo "DM Trial study_id: $DM_STUDY_ID"

# ---------------------------------------------------------------
# 1. Check if Vital Signs CRF exists
# ---------------------------------------------------------------
CRF_DATA=$(oc_query "SELECT crf_id, name FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' AND status_id != 3 LIMIT 1")

CRF_EXISTS="false"
CRF_ID=""
CRF_NAME=""
if [ -n "$CRF_DATA" ]; then
    CRF_EXISTS="true"
    CRF_ID=$(echo "$CRF_DATA" | cut -d'|' -f1)
    CRF_NAME=$(echo "$CRF_DATA" | cut -d'|' -f2)
    echo "Vital Signs CRF found: id=$CRF_ID, name=$CRF_NAME"
else
    # Fallback: partial match
    CRF_DATA=$(oc_query "SELECT crf_id, name FROM crf WHERE LOWER(name) LIKE '%vital%' AND status_id != 3 ORDER BY crf_id DESC LIMIT 1")
    if [ -n "$CRF_DATA" ]; then
        CRF_EXISTS="true"
        CRF_ID=$(echo "$CRF_DATA" | cut -d'|' -f1)
        CRF_NAME=$(echo "$CRF_DATA" | cut -d'|' -f2)
        echo "Vital Signs CRF found (partial match): id=$CRF_ID, name=$CRF_NAME"
    else
        echo "No Vital Signs CRF found in database"
    fi
fi

# Get CRF version id if CRF exists
CRF_VERSION_ID=""
CRF_VERSION_NAME=""
if [ -n "$CRF_ID" ]; then
    CRF_VERSION_DATA=$(oc_query "SELECT crf_version_id, name FROM crf_version WHERE crf_id = $CRF_ID ORDER BY crf_version_id DESC LIMIT 1")
    if [ -n "$CRF_VERSION_DATA" ]; then
        CRF_VERSION_ID=$(echo "$CRF_VERSION_DATA" | cut -d'|' -f1)
        CRF_VERSION_NAME=$(echo "$CRF_VERSION_DATA" | cut -d'|' -f2)
        echo "CRF version: id=$CRF_VERSION_ID, name=$CRF_VERSION_NAME"
    fi
fi

# ---------------------------------------------------------------
# 2. Get Baseline Assessment SED id in DM Trial
# ---------------------------------------------------------------
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
echo "Baseline Assessment SED id: $BASELINE_SED_ID"

# ---------------------------------------------------------------
# 3. Get Follow-up Visit SED id in DM Trial
# ---------------------------------------------------------------
FOLLOWUP_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Follow-up Visit' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
echo "Follow-up Visit SED id: $FOLLOWUP_SED_ID"

# ---------------------------------------------------------------
# 4. Check event_definition_crf for Vital Signs -> Baseline Assessment
# ---------------------------------------------------------------
EDC_BASELINE="0"
EDC_BASELINE_ID=""
if [ -n "$BASELINE_SED_ID" ] && [ -n "$CRF_ID" ]; then
    # Try with crf_id directly
    EDC_BASELINE=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN crf c ON edc.crf_id = c.crf_id WHERE edc.study_event_definition_id = $BASELINE_SED_ID AND c.name = 'Vital Signs' AND edc.status_id != 3")
    # Fallback via crf_version
    if [ -z "$EDC_BASELINE" ] || [ "$EDC_BASELINE" = "0" ]; then
        EDC_BASELINE=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN crf_version cv ON edc.crf_version_id = cv.crf_version_id JOIN crf c ON cv.crf_id = c.crf_id WHERE edc.study_event_definition_id = $BASELINE_SED_ID AND c.name = 'Vital Signs' AND edc.status_id != 3")
    fi
    # Also try a broad partial match
    if [ -z "$EDC_BASELINE" ] || [ "$EDC_BASELINE" = "0" ]; then
        EDC_BASELINE=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN crf c ON edc.crf_id = c.crf_id WHERE edc.study_event_definition_id = $BASELINE_SED_ID AND LOWER(c.name) LIKE '%vital%' AND edc.status_id != 3")
    fi
fi
echo "EDC Baseline count: $EDC_BASELINE"
CRF_ASSIGNED_TO_BASELINE="false"
if [ -n "$EDC_BASELINE" ] && [ "$EDC_BASELINE" != "0" ] && [ "$EDC_BASELINE" -gt 0 ] 2>/dev/null; then
    CRF_ASSIGNED_TO_BASELINE="true"
fi

# ---------------------------------------------------------------
# 5. Check event_definition_crf for Vital Signs -> Follow-up Visit
# ---------------------------------------------------------------
EDC_FOLLOWUP="0"
if [ -n "$FOLLOWUP_SED_ID" ] && [ -n "$CRF_ID" ]; then
    # Try with crf_id directly
    EDC_FOLLOWUP=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN crf c ON edc.crf_id = c.crf_id WHERE edc.study_event_definition_id = $FOLLOWUP_SED_ID AND c.name = 'Vital Signs' AND edc.status_id != 3")
    # Fallback via crf_version
    if [ -z "$EDC_FOLLOWUP" ] || [ "$EDC_FOLLOWUP" = "0" ]; then
        EDC_FOLLOWUP=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN crf_version cv ON edc.crf_version_id = cv.crf_version_id JOIN crf c ON cv.crf_id = c.crf_id WHERE edc.study_event_definition_id = $FOLLOWUP_SED_ID AND c.name = 'Vital Signs' AND edc.status_id != 3")
    fi
    # Also try a broad partial match
    if [ -z "$EDC_FOLLOWUP" ] || [ "$EDC_FOLLOWUP" = "0" ]; then
        EDC_FOLLOWUP=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc JOIN crf c ON edc.crf_id = c.crf_id WHERE edc.study_event_definition_id = $FOLLOWUP_SED_ID AND LOWER(c.name) LIKE '%vital%' AND edc.status_id != 3")
    fi
fi
echo "EDC Follow-up count: $EDC_FOLLOWUP"
CRF_ASSIGNED_TO_FOLLOWUP="false"
if [ -n "$EDC_FOLLOWUP" ] && [ "$EDC_FOLLOWUP" != "0" ] && [ "$EDC_FOLLOWUP" -gt 0 ] 2>/dev/null; then
    CRF_ASSIGNED_TO_FOLLOWUP="true"
fi

# ---------------------------------------------------------------
# 6. Get DM-102's study_subject_id
# ---------------------------------------------------------------
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
echo "DM-102 study_subject_id: $DM102_SS_ID"

# ---------------------------------------------------------------
# 7. Check study_event for DM-102 Baseline Assessment
# ---------------------------------------------------------------
DM102_EVENT_FOUND="false"
DM102_EVENT_ID=""
DM102_EVENT_DATE=""
DM102_EVENT_DATE_CORRECT="false"

if [ -n "$DM102_SS_ID" ] && [ -n "$BASELINE_SED_ID" ]; then
    DM102_EVENT_DATA=$(oc_query "SELECT se.study_event_id, se.start_date, se.status FROM study_event se WHERE se.study_subject_id = $DM102_SS_ID AND se.study_event_definition_id = $BASELINE_SED_ID ORDER BY se.study_event_id DESC LIMIT 1")
    if [ -n "$DM102_EVENT_DATA" ]; then
        DM102_EVENT_FOUND="true"
        DM102_EVENT_ID=$(echo "$DM102_EVENT_DATA" | cut -d'|' -f1)
        DM102_EVENT_DATE=$(echo "$DM102_EVENT_DATA" | cut -d'|' -f2)
        if echo "$DM102_EVENT_DATE" | grep -q "2024-02-05"; then
            DM102_EVENT_DATE_CORRECT="true"
        fi
        echo "DM-102 Baseline event: id=$DM102_EVENT_ID, date=$DM102_EVENT_DATE"
    fi
fi
echo "DM-102 event_found=$DM102_EVENT_FOUND, date_correct=$DM102_EVENT_DATE_CORRECT"

# ---------------------------------------------------------------
# 8. Check event_crf for DM-102's Baseline Assessment (data entry)
# ---------------------------------------------------------------
EVENT_CRF_EXISTS="false"
EVENT_CRF_ID=""
ITEM_DATA_COUNT="0"
HAS_SYSTOLIC="false"
HAS_DIASTOLIC="false"
HAS_HEART_RATE="false"
HAS_EXPECTED_VALUES="false"

if [ -n "$DM102_EVENT_ID" ]; then
    EVENT_CRF_DATA=$(oc_query "SELECT ec.event_crf_id, ec.status_id FROM event_crf ec WHERE ec.study_event_id = $DM102_EVENT_ID ORDER BY ec.event_crf_id DESC LIMIT 1")
    if [ -n "$EVENT_CRF_DATA" ]; then
        EVENT_CRF_EXISTS="true"
        EVENT_CRF_ID=$(echo "$EVENT_CRF_DATA" | cut -d'|' -f1)
        echo "event_crf found: id=$EVENT_CRF_ID"
    fi
fi

# Also try to find event_crf via study_subject_id if event_id not found
if [ "$EVENT_CRF_EXISTS" = "false" ] && [ -n "$DM102_SS_ID" ]; then
    EVENT_CRF_DATA=$(oc_query "SELECT ec.event_crf_id, ec.status_id FROM event_crf ec WHERE ec.study_subject_id = $DM102_SS_ID ORDER BY ec.event_crf_id DESC LIMIT 1")
    if [ -n "$EVENT_CRF_DATA" ]; then
        EVENT_CRF_EXISTS="true"
        EVENT_CRF_ID=$(echo "$EVENT_CRF_DATA" | cut -d'|' -f1)
        echo "event_crf found (via study_subject_id): id=$EVENT_CRF_ID"
    fi
fi

# ---------------------------------------------------------------
# 9. Count item_data rows and check for expected values
# ---------------------------------------------------------------
if [ -n "$EVENT_CRF_ID" ]; then
    ITEM_DATA_COUNT=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND status_id != 3")
    echo "item_data count for event_crf=$EVENT_CRF_ID: $ITEM_DATA_COUNT"

    # Check for the expected numeric values
    SYSTOLIC_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '135' AND status_id != 3")
    DIASTOLIC_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '88' AND status_id != 3")
    HEART_RATE_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '78' AND status_id != 3")

    if [ -n "$SYSTOLIC_CHECK" ] && [ "$SYSTOLIC_CHECK" -gt 0 ] 2>/dev/null; then
        HAS_SYSTOLIC="true"
    fi
    if [ -n "$DIASTOLIC_CHECK" ] && [ "$DIASTOLIC_CHECK" -gt 0 ] 2>/dev/null; then
        HAS_DIASTOLIC="true"
    fi
    if [ -n "$HEART_RATE_CHECK" ] && [ "$HEART_RATE_CHECK" -gt 0 ] 2>/dev/null; then
        HAS_HEART_RATE="true"
    fi
    if [ "$HAS_SYSTOLIC" = "true" ] || [ "$HAS_DIASTOLIC" = "true" ]; then
        HAS_EXPECTED_VALUES="true"
    fi
    echo "Values check: systolic(135)=$HAS_SYSTOLIC, diastolic(88)=$HAS_DIASTOLIC, heart_rate(78)=$HAS_HEART_RATE"
fi

# ---------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit log count=$AUDIT_LOG_COUNT, baseline=$AUDIT_BASELINE_COUNT"

# Escape strings for JSON
CRF_NAME_ESC=$(json_escape "${CRF_NAME:-}")
CRF_VERSION_NAME_ESC=$(json_escape "${CRF_VERSION_NAME:-}")
DM102_EVENT_DATE_ESC=$(json_escape "${DM102_EVENT_DATE:-}")

TEMP_JSON=$(mktemp /tmp/crf_assignment_and_entry_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "crf_exists": $CRF_EXISTS,
    "crf_id": "${CRF_ID:-}",
    "crf_name": "$CRF_NAME_ESC",
    "crf_version_id": "${CRF_VERSION_ID:-}",
    "crf_version_name": "$CRF_VERSION_NAME_ESC",
    "baseline_sed_id": "${BASELINE_SED_ID:-}",
    "followup_sed_id": "${FOLLOWUP_SED_ID:-}",
    "crf_assigned_to_baseline": $CRF_ASSIGNED_TO_BASELINE,
    "crf_assigned_to_followup": $CRF_ASSIGNED_TO_FOLLOWUP,
    "dm102_ss_id": "${DM102_SS_ID:-}",
    "dm102_baseline_event_exists": $DM102_EVENT_FOUND,
    "dm102_baseline_event_id": "${DM102_EVENT_ID:-}",
    "dm102_baseline_event_date": "$DM102_EVENT_DATE_ESC",
    "dm102_baseline_event_date_correct": $DM102_EVENT_DATE_CORRECT,
    "event_crf_exists": $EVENT_CRF_EXISTS,
    "event_crf_id": "${EVENT_CRF_ID:-}",
    "item_data_count": ${ITEM_DATA_COUNT:-0},
    "has_systolic_value": $HAS_SYSTOLIC,
    "has_diastolic_value": $HAS_DIASTOLIC,
    "has_heart_rate_value": $HAS_HEART_RATE,
    "has_expected_values": $HAS_EXPECTED_VALUES,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/crf_assignment_and_entry_result.json"

echo ""
echo "=== Export complete ==="
