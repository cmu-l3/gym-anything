#!/bin/bash
echo "=== Exporting e2e_study_activation result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual evidence
take_screenshot /tmp/task_end_screenshot.png

# ---------------------------------------------------------------
# Fetch baselines
# ---------------------------------------------------------------
BASELINE_MAX_STUDY_ID=$(cat /tmp/baseline_max_study_id 2>/dev/null || echo "0")
TASK_START_TS=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ===============================================================
# 1. Check if ONC-301 study exists and get metadata
# ===============================================================
STUDY_DATA=$(oc_query "SELECT study_id, name, principal_investigator, sponsor, protocol_type FROM study WHERE unique_identifier = 'ONC-301' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")

STUDY_EXISTS="false"
STUDY_ID="0"
STUDY_NAME=""
STUDY_PI=""
STUDY_SPONSOR=""
STUDY_PROTOCOL_TYPE=""

if [ -n "$STUDY_DATA" ]; then
    STUDY_EXISTS="true"
    STUDY_ID=$(echo "$STUDY_DATA" | cut -d'|' -f1)
    STUDY_NAME=$(echo "$STUDY_DATA" | cut -d'|' -f2)
    STUDY_PI=$(echo "$STUDY_DATA" | cut -d'|' -f3)
    STUDY_SPONSOR=$(echo "$STUDY_DATA" | cut -d'|' -f4)
    STUDY_PROTOCOL_TYPE=$(echo "$STUDY_DATA" | cut -d'|' -f5)
    echo "Study Found: id=$STUDY_ID, name='$STUDY_NAME'"
else
    echo "Study 'ONC-301' NOT found."
fi

# Get expected enrollment from study summary/enrollment field
EXPECTED_ENROLLMENT=""
if [ "$STUDY_EXISTS" = "true" ]; then
    EXPECTED_ENROLLMENT=$(oc_query "SELECT expected_total_enrollment FROM study WHERE study_id = $STUDY_ID LIMIT 1" 2>/dev/null || echo "")
fi

# ===============================================================
# 2. Check event definitions (Screening, Baseline Assessment, Cycle 1 Day 1)
# ===============================================================
SCREENING_EXISTS="false"
SCREENING_TYPE=""
SCREENING_REPEATING=""
SCREENING_SED_ID=""

BASELINE_EXISTS="false"
BASELINE_TYPE=""
BASELINE_REPEATING=""

CYCLE1_EXISTS="false"
CYCLE1_TYPE=""
CYCLE1_REPEATING=""

if [ "$STUDY_EXISTS" = "true" ]; then
    # Screening
    SCR_DATA=$(oc_query "SELECT study_event_definition_id, type, repeating::text FROM study_event_definition WHERE study_id = $STUDY_ID AND LOWER(name) LIKE '%screening%' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$SCR_DATA" ]; then
        SCREENING_EXISTS="true"
        SCREENING_SED_ID=$(echo "$SCR_DATA" | cut -d'|' -f1)
        SCREENING_TYPE=$(echo "$SCR_DATA" | cut -d'|' -f2)
        SCREENING_REPEATING=$(echo "$SCR_DATA" | cut -d'|' -f3)
    fi

    # Baseline Assessment
    BAS_DATA=$(oc_query "SELECT type, repeating::text FROM study_event_definition WHERE study_id = $STUDY_ID AND LOWER(name) LIKE '%baseline%' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$BAS_DATA" ]; then
        BASELINE_EXISTS="true"
        BASELINE_TYPE=$(echo "$BAS_DATA" | cut -d'|' -f1)
        BASELINE_REPEATING=$(echo "$BAS_DATA" | cut -d'|' -f2)
    fi

    # Cycle 1 Day 1
    C1D1_DATA=$(oc_query "SELECT type, repeating::text FROM study_event_definition WHERE study_id = $STUDY_ID AND LOWER(name) LIKE '%cycle%1%day%1%' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$C1D1_DATA" ]; then
        CYCLE1_EXISTS="true"
        CYCLE1_TYPE=$(echo "$C1D1_DATA" | cut -d'|' -f1)
        CYCLE1_REPEATING=$(echo "$C1D1_DATA" | cut -d'|' -f2)
    fi
fi

echo "Events: screening=$SCREENING_EXISTS, baseline=$BASELINE_EXISTS, cycle1=$CYCLE1_EXISTS"

# ===============================================================
# 3. Check if Vital Signs CRF exists
# ===============================================================
CRF_EXISTS="false"
CRF_ID=""
CRF_NAME=""

CRF_DATA=$(oc_query "SELECT crf_id, name FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
if [ -z "$CRF_DATA" ]; then
    # Fallback: partial match
    CRF_DATA=$(oc_query "SELECT crf_id, name FROM crf WHERE LOWER(name) LIKE '%vital%' AND status_id != 3 ORDER BY crf_id DESC LIMIT 1" 2>/dev/null || echo "")
fi

if [ -n "$CRF_DATA" ]; then
    CRF_EXISTS="true"
    CRF_ID=$(echo "$CRF_DATA" | cut -d'|' -f1)
    CRF_NAME=$(echo "$CRF_DATA" | cut -d'|' -f2)
    echo "CRF found: id=$CRF_ID, name='$CRF_NAME'"
else
    echo "Vital Signs CRF NOT found."
fi

# ===============================================================
# 4. Check CRF assignment to events
# ===============================================================
CRF_ASSIGNED_COUNT="0"
if [ "$STUDY_EXISTS" = "true" ] && [ -n "$CRF_ID" ]; then
    CRF_ASSIGNED_COUNT=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc
        JOIN study_event_definition sed ON edc.study_event_definition_id = sed.study_event_definition_id
        WHERE sed.study_id = $STUDY_ID AND edc.crf_id = $CRF_ID AND edc.status_id != 3" 2>/dev/null || echo "0")

    # Fallback via crf_version
    if [ -z "$CRF_ASSIGNED_COUNT" ] || [ "$CRF_ASSIGNED_COUNT" = "0" ]; then
        CRF_ASSIGNED_COUNT=$(oc_query "SELECT COUNT(*) FROM event_definition_crf edc
            JOIN study_event_definition sed ON edc.study_event_definition_id = sed.study_event_definition_id
            JOIN crf_version cv ON edc.default_version_id = cv.crf_version_id
            WHERE sed.study_id = $STUDY_ID AND cv.crf_id = $CRF_ID AND edc.status_id != 3" 2>/dev/null || echo "0")
    fi
fi
echo "CRF assigned to $CRF_ASSIGNED_COUNT events"

# ===============================================================
# 5. Check site MRC-001 exists under ONC-301
# ===============================================================
SITE_EXISTS="false"
SITE_ID=""
SITE_NAME=""

if [ "$STUDY_EXISTS" = "true" ]; then
    SITE_DATA=$(oc_query "SELECT study_id, name FROM study WHERE parent_study_id = $STUDY_ID AND (unique_identifier = 'MRC-001' OR LOWER(name) LIKE '%memorial%') AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$SITE_DATA" ]; then
        SITE_EXISTS="true"
        SITE_ID=$(echo "$SITE_DATA" | cut -d'|' -f1)
        SITE_NAME=$(echo "$SITE_DATA" | cut -d'|' -f2)
        echo "Site found: id=$SITE_ID, name='$SITE_NAME'"
    else
        echo "Site MRC-001 NOT found under ONC-301."
    fi
fi

# ===============================================================
# 6. Check subject ONC-001 enrolled
# ===============================================================
SUBJECT_ENROLLED="false"
SUBJECT_ENROLLED_AT_SITE="false"
SUBJECT_SS_ID=""
SUBJECT_GENDER=""
SUBJECT_DOB=""

if [ "$STUDY_EXISTS" = "true" ]; then
    # Check site-level enrollment first
    if [ -n "$SITE_ID" ]; then
        SUBJ_DATA=$(oc_query "SELECT ss.study_subject_id, sub.gender, sub.date_of_birth
            FROM study_subject ss JOIN subject sub ON ss.subject_id = sub.subject_id
            WHERE ss.label = 'ONC-001' AND ss.study_id = $SITE_ID AND ss.status_id != 3 LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$SUBJ_DATA" ]; then
            SUBJECT_ENROLLED="true"
            SUBJECT_ENROLLED_AT_SITE="true"
            SUBJECT_SS_ID=$(echo "$SUBJ_DATA" | cut -d'|' -f1)
            SUBJECT_GENDER=$(echo "$SUBJ_DATA" | cut -d'|' -f2)
            SUBJECT_DOB=$(echo "$SUBJ_DATA" | cut -d'|' -f3)
        fi
    fi

    # Fallback: check parent study enrollment
    if [ "$SUBJECT_ENROLLED" = "false" ]; then
        SUBJ_DATA=$(oc_query "SELECT ss.study_subject_id, sub.gender, sub.date_of_birth
            FROM study_subject ss JOIN subject sub ON ss.subject_id = sub.subject_id
            WHERE ss.label = 'ONC-001' AND ss.study_id = $STUDY_ID AND ss.status_id != 3 LIMIT 1" 2>/dev/null || echo "")
        if [ -n "$SUBJ_DATA" ]; then
            SUBJECT_ENROLLED="true"
            SUBJECT_SS_ID=$(echo "$SUBJ_DATA" | cut -d'|' -f1)
            SUBJECT_GENDER=$(echo "$SUBJ_DATA" | cut -d'|' -f2)
            SUBJECT_DOB=$(echo "$SUBJ_DATA" | cut -d'|' -f3)
        fi
    fi
fi
echo "Subject ONC-001: enrolled=$SUBJECT_ENROLLED, at_site=$SUBJECT_ENROLLED_AT_SITE, gender=$SUBJECT_GENDER, dob=$SUBJECT_DOB"

# ===============================================================
# 7. Check Screening event scheduled for ONC-001
# ===============================================================
SCREENING_EVENT_FOUND="false"
SCREENING_EVENT_DATE=""

if [ -n "$SUBJECT_SS_ID" ] && [ -n "$SCREENING_SED_ID" ]; then
    SE_DATA=$(oc_query "SELECT date_start FROM study_event
        WHERE study_subject_id = $SUBJECT_SS_ID
        AND study_event_definition_id = $SCREENING_SED_ID
        ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$SE_DATA" ]; then
        SCREENING_EVENT_FOUND="true"
        SCREENING_EVENT_DATE="$SE_DATA"
    fi
fi

# Also check all events for this subject if screening SED ID wasn't resolved
if [ "$SCREENING_EVENT_FOUND" = "false" ] && [ -n "$SUBJECT_SS_ID" ]; then
    SE_DATA=$(oc_query "SELECT se.date_start, sed.name FROM study_event se
        JOIN study_event_definition sed ON se.study_event_definition_id = sed.study_event_definition_id
        WHERE se.study_subject_id = $SUBJECT_SS_ID
        AND LOWER(sed.name) LIKE '%screening%'
        ORDER BY se.study_event_id DESC LIMIT 1" 2>/dev/null || echo "")
    if [ -n "$SE_DATA" ]; then
        SCREENING_EVENT_FOUND="true"
        SCREENING_EVENT_DATE=$(echo "$SE_DATA" | cut -d'|' -f1)
    fi
fi
echo "Screening event: found=$SCREENING_EVENT_FOUND, date=$SCREENING_EVENT_DATE"

# ===============================================================
# 8. Check CRF data entry (item_data) for ONC-001's Screening
# ===============================================================
EVENT_CRF_EXISTS="false"
EVENT_CRF_STATUS=""
ITEM_DATA_COUNT="0"
HAS_SYSTOLIC="false"
HAS_DIASTOLIC="false"
HAS_HEART_RATE="false"
HAS_TEMPERATURE="false"
HAS_WEIGHT="false"
HAS_HEIGHT="false"

if [ -n "$SUBJECT_SS_ID" ]; then
    # Find event_crf for this subject's event
    EC_DATA=$(oc_query "SELECT ec.event_crf_id, ec.status_id FROM event_crf ec
        JOIN study_event se ON ec.study_event_id = se.study_event_id
        WHERE se.study_subject_id = $SUBJECT_SS_ID
        ORDER BY ec.event_crf_id DESC LIMIT 1" 2>/dev/null || echo "")

    if [ -n "$EC_DATA" ]; then
        EVENT_CRF_EXISTS="true"
        EVENT_CRF_ID=$(echo "$EC_DATA" | cut -d'|' -f1)
        EVENT_CRF_STATUS=$(echo "$EC_DATA" | cut -d'|' -f2)
        echo "event_crf found: id=$EVENT_CRF_ID, status=$EVENT_CRF_STATUS"

        # Count item_data rows
        ITEM_DATA_COUNT=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND status_id != 3" 2>/dev/null || echo "0")
        echo "item_data count: $ITEM_DATA_COUNT"

        # Check for expected values
        SYSTOLIC_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '142' AND status_id != 3" 2>/dev/null || echo "0")
        DIASTOLIC_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '88' AND status_id != 3" 2>/dev/null || echo "0")
        HR_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '76' AND status_id != 3" 2>/dev/null || echo "0")
        TEMP_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '37.1' AND status_id != 3" 2>/dev/null || echo "0")
        WEIGHT_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '81.4' AND status_id != 3" 2>/dev/null || echo "0")
        HEIGHT_CHECK=$(oc_query "SELECT COUNT(*) FROM item_data WHERE event_crf_id = $EVENT_CRF_ID AND value = '175.0' AND status_id != 3" 2>/dev/null || echo "0")

        [ -n "$SYSTOLIC_CHECK" ] && [ "$SYSTOLIC_CHECK" -gt 0 ] 2>/dev/null && HAS_SYSTOLIC="true"
        [ -n "$DIASTOLIC_CHECK" ] && [ "$DIASTOLIC_CHECK" -gt 0 ] 2>/dev/null && HAS_DIASTOLIC="true"
        [ -n "$HR_CHECK" ] && [ "$HR_CHECK" -gt 0 ] 2>/dev/null && HAS_HEART_RATE="true"
        [ -n "$TEMP_CHECK" ] && [ "$TEMP_CHECK" -gt 0 ] 2>/dev/null && HAS_TEMPERATURE="true"
        [ -n "$WEIGHT_CHECK" ] && [ "$WEIGHT_CHECK" -gt 0 ] 2>/dev/null && HAS_WEIGHT="true"
        [ -n "$HEIGHT_CHECK" ] && [ "$HEIGHT_CHECK" -gt 0 ] 2>/dev/null && HAS_HEIGHT="true"

        echo "Values: sys=$HAS_SYSTOLIC, dia=$HAS_DIASTOLIC, hr=$HAS_HEART_RATE, temp=$HAS_TEMPERATURE, wt=$HAS_WEIGHT, ht=$HAS_HEIGHT"
    fi
fi

# ===============================================================
# 9. Audit log and nonce
# ===============================================================
AUDIT_LOG_COUNT=$(get_recent_audit_count 120)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit: current=$AUDIT_LOG_COUNT, baseline=$AUDIT_BASELINE_COUNT"

# ===============================================================
# 10. Write result JSON
# ===============================================================
TEMP_JSON=$(mktemp /tmp/e2e_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "baseline_max_study_id": $BASELINE_MAX_STUDY_ID,
    "study_exists": $STUDY_EXISTS,
    "study_id": $STUDY_ID,
    "study_name": "$(json_escape "${STUDY_NAME:-}")",
    "study_pi": "$(json_escape "${STUDY_PI:-}")",
    "study_sponsor": "$(json_escape "${STUDY_SPONSOR:-}")",
    "study_protocol_type": "$(json_escape "${STUDY_PROTOCOL_TYPE:-}")",
    "expected_enrollment": "$(json_escape "${EXPECTED_ENROLLMENT:-}")",

    "screening_event_def_exists": $SCREENING_EXISTS,
    "screening_event_def_type": "$(json_escape "${SCREENING_TYPE:-}")",
    "screening_event_def_repeating": "$(json_escape "${SCREENING_REPEATING:-}")",
    "baseline_event_def_exists": $BASELINE_EXISTS,
    "baseline_event_def_type": "$(json_escape "${BASELINE_TYPE:-}")",
    "baseline_event_def_repeating": "$(json_escape "${BASELINE_REPEATING:-}")",
    "cycle1_event_def_exists": $CYCLE1_EXISTS,
    "cycle1_event_def_type": "$(json_escape "${CYCLE1_TYPE:-}")",
    "cycle1_event_def_repeating": "$(json_escape "${CYCLE1_REPEATING:-}")",

    "crf_exists": $CRF_EXISTS,
    "crf_id": "${CRF_ID:-}",
    "crf_name": "$(json_escape "${CRF_NAME:-}")",
    "crf_assigned_event_count": ${CRF_ASSIGNED_COUNT:-0},

    "site_exists": $SITE_EXISTS,
    "site_id": "${SITE_ID:-}",
    "site_name": "$(json_escape "${SITE_NAME:-}")",

    "subject_enrolled": $SUBJECT_ENROLLED,
    "subject_enrolled_at_site": $SUBJECT_ENROLLED_AT_SITE,
    "subject_gender": "$(json_escape "${SUBJECT_GENDER:-}")",
    "subject_dob": "$(json_escape "${SUBJECT_DOB:-}")",

    "screening_event_found": $SCREENING_EVENT_FOUND,
    "screening_event_date": "$(json_escape "${SCREENING_EVENT_DATE:-}")",

    "event_crf_exists": $EVENT_CRF_EXISTS,
    "event_crf_status": "${EVENT_CRF_STATUS:-}",
    "item_data_count": ${ITEM_DATA_COUNT:-0},
    "has_systolic": $HAS_SYSTOLIC,
    "has_diastolic": $HAS_DIASTOLIC,
    "has_heart_rate": $HAS_HEART_RATE,
    "has_temperature": $HAS_TEMPERATURE,
    "has_weight": $HAS_WEIGHT,
    "has_height": $HAS_HEIGHT,

    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/e2e_study_activation_result.json"

echo ""
echo "=== Export complete ==="
