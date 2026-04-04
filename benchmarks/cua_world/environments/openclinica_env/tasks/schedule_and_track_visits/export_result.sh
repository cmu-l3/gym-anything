#!/bin/bash
echo "=== Exporting schedule_and_track_visits result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Get study IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
echo "DM Trial study_id: $DM_STUDY_ID"

INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count 2>/dev/null || echo "0")
INITIAL_SUBJECT_COUNT=$(cat /tmp/initial_subject_count 2>/dev/null || echo "0")

# --- Check DM-101 Baseline Assessment ---
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

DM101_EVENT_DATA=""
DM101_EVENT_FOUND="false"
DM101_EVENT_DATE=""
DM101_EVENT_DATE_CORRECT="false"
if [ -n "$DM101_SS_ID" ] && [ -n "$BASELINE_SED_ID" ]; then
    DM101_EVENT_DATA=$(oc_query "SELECT se.study_event_id, se.start_date, se.status FROM study_event se WHERE se.study_subject_id = $DM101_SS_ID AND se.study_event_definition_id = $BASELINE_SED_ID ORDER BY se.study_event_id DESC LIMIT 1")
    if [ -n "$DM101_EVENT_DATA" ]; then
        DM101_EVENT_FOUND="true"
        DM101_EVENT_DATE=$(echo "$DM101_EVENT_DATA" | cut -d'|' -f2)
        # Check if date is 2024-01-15
        if echo "$DM101_EVENT_DATE" | grep -q "2024-01-15"; then
            DM101_EVENT_DATE_CORRECT="true"
        fi
    fi
fi
echo "DM-101 Baseline: found=$DM101_EVENT_FOUND, date=$DM101_EVENT_DATE, date_correct=$DM101_EVENT_DATE_CORRECT"

# --- Check DM-102 Week 4 Follow-up ---
DM102_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
WEEK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

DM102_EVENT_FOUND="false"
DM102_EVENT_DATE=""
DM102_EVENT_DATE_CORRECT="false"
if [ -n "$DM102_SS_ID" ] && [ -n "$WEEK4_SED_ID" ]; then
    DM102_EVENT_DATA=$(oc_query "SELECT se.study_event_id, se.start_date, se.status FROM study_event se WHERE se.study_subject_id = $DM102_SS_ID AND se.study_event_definition_id = $WEEK4_SED_ID ORDER BY se.study_event_id DESC LIMIT 1")
    if [ -n "$DM102_EVENT_DATA" ]; then
        DM102_EVENT_FOUND="true"
        DM102_EVENT_DATE=$(echo "$DM102_EVENT_DATA" | cut -d'|' -f2)
        if echo "$DM102_EVENT_DATE" | grep -q "2024-03-01"; then
            DM102_EVENT_DATE_CORRECT="true"
        fi
    fi
fi
echo "DM-102 Week4: found=$DM102_EVENT_FOUND, date=$DM102_EVENT_DATE, date_correct=$DM102_EVENT_DATE_CORRECT"

# --- Check DM-104 enrollment ---
DM104_SS_ID=$(oc_query "SELECT ss.study_subject_id FROM study_subject ss WHERE ss.label = 'DM-104' AND ss.study_id = $DM_STUDY_ID LIMIT 1")
DM104_ENROLLED="false"
DM104_GENDER=""
DM104_DOB=""

if [ -n "$DM104_SS_ID" ]; then
    DM104_ENROLLED="true"
    DM104_DATA=$(oc_query "SELECT sb.gender, sb.date_of_birth, ss.enrollment_date FROM study_subject ss JOIN subject sb ON ss.subject_id = sb.subject_id WHERE ss.study_subject_id = $DM104_SS_ID LIMIT 1")
    DM104_GENDER=$(echo "$DM104_DATA" | cut -d'|' -f1)
    DM104_DOB=$(echo "$DM104_DATA" | cut -d'|' -f2)
fi
echo "DM-104: enrolled=$DM104_ENROLLED, gender=$DM104_GENDER, dob=$DM104_DOB"

# --- Check DM-104 Baseline Assessment event ---
DM104_EVENT_FOUND="false"
DM104_EVENT_DATE=""
DM104_EVENT_DATE_CORRECT="false"
if [ -n "$DM104_SS_ID" ] && [ -n "$BASELINE_SED_ID" ]; then
    DM104_EVENT_DATA=$(oc_query "SELECT se.study_event_id, se.start_date FROM study_event se WHERE se.study_subject_id = $DM104_SS_ID AND se.study_event_definition_id = $BASELINE_SED_ID ORDER BY se.study_event_id DESC LIMIT 1")
    if [ -n "$DM104_EVENT_DATA" ]; then
        DM104_EVENT_FOUND="true"
        DM104_EVENT_DATE=$(echo "$DM104_EVENT_DATA" | cut -d'|' -f2)
        if echo "$DM104_EVENT_DATE" | grep -q "2024-01-22"; then
            DM104_EVENT_DATE_CORRECT="true"
        fi
    fi
fi
echo "DM-104 Baseline event: found=$DM104_EVENT_FOUND, date=$DM104_EVENT_DATE"

# Current counts
CURRENT_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event se JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id WHERE ss.study_id = $DM_STUDY_ID")
CURRENT_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE study_id = $DM_STUDY_ID AND status_id != 3")

# Audit log
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/schedule_visits_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_event_count": ${INITIAL_EVENT_COUNT:-0},
    "current_event_count": ${CURRENT_EVENT_COUNT:-0},
    "initial_subject_count": ${INITIAL_SUBJECT_COUNT:-0},
    "current_subject_count": ${CURRENT_SUBJECT_COUNT:-0},
    "dm101_event_found": $DM101_EVENT_FOUND,
    "dm101_event_date": "$(json_escape "${DM101_EVENT_DATE:-}")",
    "dm101_event_date_correct": $DM101_EVENT_DATE_CORRECT,
    "dm102_event_found": $DM102_EVENT_FOUND,
    "dm102_event_date": "$(json_escape "${DM102_EVENT_DATE:-}")",
    "dm102_event_date_correct": $DM102_EVENT_DATE_CORRECT,
    "dm104_enrolled": $DM104_ENROLLED,
    "dm104_gender": "$(json_escape "${DM104_GENDER:-}")",
    "dm104_dob": "$(json_escape "${DM104_DOB:-}")",
    "dm104_event_found": $DM104_EVENT_FOUND,
    "dm104_event_date": "$(json_escape "${DM104_EVENT_DATE:-}")",
    "dm104_event_date_correct": $DM104_EVENT_DATE_CORRECT,
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/schedule_and_track_visits_result.json"

echo "=== Export complete ==="
