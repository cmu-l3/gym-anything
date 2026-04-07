#!/bin/bash
echo "=== Exporting build_registry_protocol result ==="

source /workspace/scripts/task_utils.sh

# Record end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

CV_STUDY_ID=$(cat /tmp/cv_study_id.txt 2>/dev/null)
if [ -z "$CV_STUDY_ID" ]; then
    CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
fi

# Initialize JSON strings
JSON_EVENTS=""
JSON_SUBJECTS=""
JSON_SCHEDULES=""

# --- 1. Check Event Definitions ---
echo "Checking event definitions..."

# Event 1: Enrollment Visit
EV1_DATA=$(oc_query "SELECT type, repeating::text, name FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND LOWER(name) LIKE '%enroll%' AND status_id != 3 LIMIT 1" 2>/dev/null)
EV1_FOUND="false"; EV1_TYPE=""; EV1_REPEATING=""
if [ -n "$EV1_DATA" ]; then
    EV1_FOUND="true"
    EV1_TYPE=$(echo "$EV1_DATA" | cut -d'|' -f1)
    EV1_REPEATING=$(echo "$EV1_DATA" | cut -d'|' -f2)
fi

# Event 2: Quarterly Follow-up
EV2_DATA=$(oc_query "SELECT type, repeating::text, name FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND (LOWER(name) LIKE '%quarterly%' OR LOWER(name) LIKE '%follow%up%') AND status_id != 3 LIMIT 1" 2>/dev/null)
EV2_FOUND="false"; EV2_TYPE=""; EV2_REPEATING=""
if [ -n "$EV2_DATA" ]; then
    EV2_FOUND="true"
    EV2_TYPE=$(echo "$EV2_DATA" | cut -d'|' -f1)
    EV2_REPEATING=$(echo "$EV2_DATA" | cut -d'|' -f2)
fi

# Event 3: Annual Comprehensive Review
EV3_DATA=$(oc_query "SELECT type, repeating::text, name FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND (LOWER(name) LIKE '%annual%' OR LOWER(name) LIKE '%comprehensive%') AND status_id != 3 LIMIT 1" 2>/dev/null)
EV3_FOUND="false"; EV3_TYPE=""; EV3_REPEATING=""
if [ -n "$EV3_DATA" ]; then
    EV3_FOUND="true"
    EV3_TYPE=$(echo "$EV3_DATA" | cut -d'|' -f1)
    EV3_REPEATING=$(echo "$EV3_DATA" | cut -d'|' -f2)
fi

# Event 4: Unscheduled Safety Assessment
EV4_DATA=$(oc_query "SELECT type, repeating::text, name FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND (LOWER(name) LIKE '%safety%' OR LOWER(name) LIKE '%unscheduled%') AND status_id != 3 LIMIT 1" 2>/dev/null)
EV4_FOUND="false"; EV4_TYPE=""; EV4_REPEATING=""
if [ -n "$EV4_DATA" ]; then
    EV4_FOUND="true"
    EV4_TYPE=$(echo "$EV4_DATA" | cut -d'|' -f1)
    EV4_REPEATING=$(echo "$EV4_DATA" | cut -d'|' -f2)
fi

# --- 2. Check Subjects ---
echo "Checking subjects..."

# Subject 1: CV-201
SUBJ1_DATA=$(oc_query "SELECT s.gender, s.date_of_birth FROM study_subject ss JOIN subject s ON ss.subject_id = s.subject_id WHERE ss.study_id = $CV_STUDY_ID AND ss.label = 'CV-201' AND ss.status_id != 3 LIMIT 1" 2>/dev/null)
SUBJ1_FOUND="false"; SUBJ1_GENDER=""; SUBJ1_DOB=""
if [ -n "$SUBJ1_DATA" ]; then
    SUBJ1_FOUND="true"
    SUBJ1_GENDER=$(echo "$SUBJ1_DATA" | cut -d'|' -f1)
    SUBJ1_DOB=$(echo "$SUBJ1_DATA" | cut -d'|' -f2)
fi

# Subject 2: CV-202
SUBJ2_DATA=$(oc_query "SELECT s.gender, s.date_of_birth FROM study_subject ss JOIN subject s ON ss.subject_id = s.subject_id WHERE ss.study_id = $CV_STUDY_ID AND ss.label = 'CV-202' AND ss.status_id != 3 LIMIT 1" 2>/dev/null)
SUBJ2_FOUND="false"; SUBJ2_GENDER=""; SUBJ2_DOB=""
if [ -n "$SUBJ2_DATA" ]; then
    SUBJ2_FOUND="true"
    SUBJ2_GENDER=$(echo "$SUBJ2_DATA" | cut -d'|' -f1)
    SUBJ2_DOB=$(echo "$SUBJ2_DATA" | cut -d'|' -f2)
fi

# --- 3. Check Scheduled Events ---
echo "Checking scheduled events..."

# CV-201 Enrollment Visit
SCHED1_DATA=$(oc_query "SELECT se.start_date FROM study_event se JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id JOIN study_event_definition sed ON se.study_event_definition_id = sed.study_event_definition_id WHERE ss.label = 'CV-201' AND ss.study_id = $CV_STUDY_ID AND LOWER(sed.name) LIKE '%enroll%' AND se.status_id != 3 LIMIT 1" 2>/dev/null)
SCHED1_FOUND="false"; SCHED1_DATE=""
if [ -n "$SCHED1_DATA" ]; then
    SCHED1_FOUND="true"
    SCHED1_DATE=$(echo "$SCHED1_DATA" | cut -d'|' -f1)
fi

# CV-202 Enrollment Visit
SCHED2_DATA=$(oc_query "SELECT se.start_date FROM study_event se JOIN study_subject ss ON se.study_subject_id = ss.study_subject_id JOIN study_event_definition sed ON se.study_event_definition_id = sed.study_event_definition_id WHERE ss.label = 'CV-202' AND ss.study_id = $CV_STUDY_ID AND LOWER(sed.name) LIKE '%enroll%' AND se.status_id != 3 LIMIT 1" 2>/dev/null)
SCHED2_FOUND="false"; SCHED2_DATE=""
if [ -n "$SCHED2_DATA" ]; then
    SCHED2_FOUND="true"
    SCHED2_DATE=$(echo "$SCHED2_DATA" | cut -d'|' -f1)
fi

# --- 4. Gather Metadata & Audits ---
CURRENT_EVENT_DEF_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $CV_STUDY_ID AND status_id != 3")
CURRENT_SUBJECT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_subject WHERE study_id = $CV_STUDY_ID AND status_id != 3")
INITIAL_EVENT_DEF_COUNT=$(cat /tmp/initial_event_def_count.txt 2>/dev/null || echo "0")
INITIAL_SUBJECT_COUNT=$(cat /tmp/initial_subject_count.txt 2>/dev/null || echo "0")

AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count.txt 2>/dev/null || echo "0")

NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write JSON output
TEMP_JSON=$(mktemp /tmp/build_registry_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "result_nonce": "$NONCE",
    "counts": {
        "initial_event_defs": ${INITIAL_EVENT_DEF_COUNT:-0},
        "current_event_defs": ${CURRENT_EVENT_DEF_COUNT:-0},
        "initial_subjects": ${INITIAL_SUBJECT_COUNT:-0},
        "current_subjects": ${CURRENT_SUBJECT_COUNT:-0},
        "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
        "audit_current": ${AUDIT_LOG_COUNT:-0}
    },
    "events": {
        "enrollment": { "found": $EV1_FOUND, "type": "$(json_escape "$EV1_TYPE")", "repeating": "$(json_escape "$EV1_REPEATING")" },
        "quarterly": { "found": $EV2_FOUND, "type": "$(json_escape "$EV2_TYPE")", "repeating": "$(json_escape "$EV2_REPEATING")" },
        "annual": { "found": $EV3_FOUND, "type": "$(json_escape "$EV3_TYPE")", "repeating": "$(json_escape "$EV3_REPEATING")" },
        "safety": { "found": $EV4_FOUND, "type": "$(json_escape "$EV4_TYPE")", "repeating": "$(json_escape "$EV4_REPEATING")" }
    },
    "subjects": {
        "cv_201": { "found": $SUBJ1_FOUND, "gender": "$(json_escape "$SUBJ1_GENDER")", "dob": "$(json_escape "$SUBJ1_DOB")" },
        "cv_202": { "found": $SUBJ2_FOUND, "gender": "$(json_escape "$SUBJ2_GENDER")", "dob": "$(json_escape "$SUBJ2_DOB")" }
    },
    "schedules": {
        "cv_201_enrollment": { "found": $SCHED1_FOUND, "date": "$(json_escape "$SCHED1_DATE")" },
        "cv_202_enrollment": { "found": $SCHED2_FOUND, "date": "$(json_escape "$SCHED2_DATE")" }
    }
}
EOF

# Move securely
rm -f /tmp/build_registry_protocol_result.json 2>/dev/null || sudo rm -f /tmp/build_registry_protocol_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/build_registry_protocol_result.json
chmod 666 /tmp/build_registry_protocol_result.json 2>/dev/null || sudo chmod 666 /tmp/build_registry_protocol_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Results saved to /tmp/build_registry_protocol_result.json"
cat /tmp/build_registry_protocol_result.json