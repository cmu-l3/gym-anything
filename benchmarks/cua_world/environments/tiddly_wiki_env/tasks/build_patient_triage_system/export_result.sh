#!/bin/bash
echo "=== Exporting build_patient_triage_system result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/triage_final.png

# ---- Check Triage Dashboard ----
DASHBOARD_TITLE="Triage Dashboard"
DASHBOARD_FOUND=$(tiddler_exists "$DASHBOARD_TITLE")
DASHBOARD_TEXT=""
DASHBOARD_TAGS=""
if [ "$DASHBOARD_FOUND" = "true" ]; then
    DASHBOARD_TEXT=$(get_tiddler_text "$DASHBOARD_TITLE")
    DASHBOARD_TAGS=$(get_tiddler_field "$DASHBOARD_TITLE" "tags")
fi

# ---- Check ViewTemplate ----
# System tiddlers use $: prefix which gets sanitized to __
VIEWTEMPLATE_TITLE='$:/custom/TriageAssessment'
VIEWTEMPLATE_FOUND="false"
VIEWTEMPLATE_TEXT=""
VIEWTEMPLATE_TAGS=""

# Try to find the system tiddler file directly
VT_FILE=$(find "$TIDDLER_DIR" -maxdepth 1 -name '*custom*TriageAssessment*' 2>/dev/null | head -1)
if [ -n "$VT_FILE" ] && [ -f "$VT_FILE" ]; then
    VIEWTEMPLATE_FOUND="true"
    VIEWTEMPLATE_TEXT=$(awk '/^$/{found=1; next} found{print}' "$VT_FILE")
    VIEWTEMPLATE_TAGS=$(grep -i "^tags:" "$VT_FILE" | head -1 | sed 's/^tags: *//')
fi

# ---- Check Waiting Room Board ----
BOARD_TITLE="Waiting Room Board"
BOARD_FOUND=$(tiddler_exists "$BOARD_TITLE")
BOARD_TEXT=""
BOARD_TAGS=""
if [ "$BOARD_FOUND" = "true" ]; then
    BOARD_TEXT=$(get_tiddler_text "$BOARD_TITLE")
    BOARD_TAGS=$(get_tiddler_field "$BOARD_TITLE" "tags")
fi

# ---- Check Patient Tiddlers ----
collect_patient_data() {
    local PATIENT_NAME="$1"
    local P_EXISTS=$(tiddler_exists "$PATIENT_NAME")
    local P_TAGS=""
    local P_TRIAGE_LEVEL=""
    local P_TRIAGE_STATUS=""
    local P_AGE=""
    local P_TEMPERATURE=""
    local P_HEART_RATE=""
    local P_BP=""
    local P_COMPLAINT=""

    if [ "$P_EXISTS" = "true" ]; then
        P_TAGS=$(get_tiddler_field "$PATIENT_NAME" "tags")
        P_TRIAGE_LEVEL=$(get_tiddler_field "$PATIENT_NAME" "triage-level")
        P_TRIAGE_STATUS=$(get_tiddler_field "$PATIENT_NAME" "triage-status")
        P_AGE=$(get_tiddler_field "$PATIENT_NAME" "age")
        P_TEMPERATURE=$(get_tiddler_field "$PATIENT_NAME" "temperature")
        P_HEART_RATE=$(get_tiddler_field "$PATIENT_NAME" "heart-rate")
        P_BP=$(get_tiddler_field "$PATIENT_NAME" "blood-pressure")
        P_COMPLAINT=$(get_tiddler_field "$PATIENT_NAME" "chief-complaint")
    fi

    # Derived checks
    local HAS_PATIENT_TAG="false"
    local HAS_WAITINGROOM_TAG="false"
    local HAS_TREATMENT_TAG="false"

    echo "$P_TAGS" | grep -qi "Patient" && HAS_PATIENT_TAG="true"
    echo "$P_TAGS" | grep -qi "WaitingRoom" && HAS_WAITINGROOM_TAG="true"
    echo "$P_TAGS" | grep -qi "Treatment" && HAS_TREATMENT_TAG="true"

    echo "{\"exists\": $P_EXISTS, \"tags\": \"$(json_escape "$P_TAGS")\", \"triage_level\": \"$(json_escape "$P_TRIAGE_LEVEL")\", \"triage_status\": \"$(json_escape "$P_TRIAGE_STATUS")\", \"age\": \"$(json_escape "$P_AGE")\", \"temperature\": \"$(json_escape "$P_TEMPERATURE")\", \"heart_rate\": \"$(json_escape "$P_HEART_RATE")\", \"blood_pressure\": \"$(json_escape "$P_BP")\", \"chief_complaint\": \"$(json_escape "$P_COMPLAINT")\", \"has_patient_tag\": $HAS_PATIENT_TAG, \"has_waitingroom_tag\": $HAS_WAITINGROOM_TAG, \"has_treatment_tag\": $HAS_TREATMENT_TAG}"
}

MARIA_DATA=$(collect_patient_data "Maria Santos")
JAMES_DATA=$(collect_patient_data "James Wilson")
AISHA_DATA=$(collect_patient_data "Aisha Patel")

# ---- Widget presence checks on Dashboard ----
HAS_EDIT_TEXT=$(echo "$DASHBOARD_TEXT" | grep -qi '<\$edit-text\|<\$edit' && echo "true" || echo "false")
HAS_BUTTON=$(echo "$DASHBOARD_TEXT" | grep -qi '<\$button' && echo "true" || echo "false")
HAS_STATE_REF=$(echo "$DASHBOARD_TEXT" | grep -qi '\$:/temp/NewPatient' && echo "true" || echo "false")
HAS_NEW_TIDDLER=$(echo "$DASHBOARD_TEXT" | grep -qi 'tm-new-tiddler\|action-createtiddler' && echo "true" || echo "false")

# ---- Widget presence checks on ViewTemplate ----
VT_HAS_ACTION_SETFIELD=$(echo "$VIEWTEMPLATE_TEXT" | grep -qi '<\$action-setfield\|action-setfield' && echo "true" || echo "false")
VT_HAS_TRIAGE_LEVEL=$(echo "$VIEWTEMPLATE_TEXT" | grep -qi 'triage-level' && echo "true" || echo "false")
VT_HAS_TREATMENT=$(echo "$VIEWTEMPLATE_TEXT" | grep -qi 'Treatment' && echo "true" || echo "false")
VT_HAS_LISTOPS=$(echo "$VIEWTEMPLATE_TEXT" | grep -qi '<\$action-listops\|action-listops' && echo "true" || echo "false")
VT_HAS_VIEWTEMPLATE_TAG=$(echo "$VIEWTEMPLATE_TAGS" | grep -q '\$:/tags/ViewTemplate' && echo "true" || echo "false")

# ---- Widget presence checks on Board ----
BOARD_HAS_LIST=$(echo "$BOARD_TEXT" | grep -qi '<\$list' && echo "true" || echo "false")
BOARD_HAS_TRIAGE_STATUS=$(echo "$BOARD_TEXT" | grep -qi 'triage-status' && echo "true" || echo "false")
BOARD_HAS_SORT=$(echo "$BOARD_TEXT" | grep -qi 'sort\[triage-level\]' && echo "true" || echo "false")

# ---- GUI save detection ----
# Only detect saves of tiddlers the agent should create, not seed data
GUI_SAVE_DETECTED="false"
if [ -f /home/ga/tiddlywiki.log ]; then
    if grep -qi "Dispatching 'save' task:.*\(Triage Dashboard\|TriageAssessment\|Waiting Room Board\|Maria Santos\|James Wilson\|Aisha Patel\)" /home/ga/tiddlywiki.log 2>/dev/null; then
        GUI_SAVE_DETECTED="true"
    fi
fi

# ---- Count new tiddlers ----
INITIAL_COUNT=$(cat /tmp/initial_tiddler_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_user_tiddlers)

# ---- Build result JSON ----
ESCAPED_DASHBOARD_TEXT=$(json_escape "$DASHBOARD_TEXT")
ESCAPED_VIEWTEMPLATE_TEXT=$(json_escape "$VIEWTEMPLATE_TEXT")
ESCAPED_BOARD_TEXT=$(json_escape "$BOARD_TEXT")

JSON_RESULT=$(cat << EOF
{
    "task_start": $TASK_START,
    "initial_tiddler_count": $INITIAL_COUNT,
    "current_tiddler_count": $CURRENT_COUNT,
    "dashboard_found": $DASHBOARD_FOUND,
    "dashboard_text": "$ESCAPED_DASHBOARD_TEXT",
    "dashboard_tags": "$(json_escape "$DASHBOARD_TAGS")",
    "dashboard_has_edit_text": $HAS_EDIT_TEXT,
    "dashboard_has_button": $HAS_BUTTON,
    "dashboard_has_state_ref": $HAS_STATE_REF,
    "dashboard_has_new_tiddler": $HAS_NEW_TIDDLER,
    "viewtemplate_found": $VIEWTEMPLATE_FOUND,
    "viewtemplate_text": "$ESCAPED_VIEWTEMPLATE_TEXT",
    "viewtemplate_tags": "$(json_escape "$VIEWTEMPLATE_TAGS")",
    "viewtemplate_has_action_setfield": $VT_HAS_ACTION_SETFIELD,
    "viewtemplate_has_triage_level": $VT_HAS_TRIAGE_LEVEL,
    "viewtemplate_has_treatment": $VT_HAS_TREATMENT,
    "viewtemplate_has_listops": $VT_HAS_LISTOPS,
    "viewtemplate_has_viewtemplate_tag": $VT_HAS_VIEWTEMPLATE_TAG,
    "board_found": $BOARD_FOUND,
    "board_text": "$ESCAPED_BOARD_TEXT",
    "board_tags": "$(json_escape "$BOARD_TAGS")",
    "board_has_list": $BOARD_HAS_LIST,
    "board_has_triage_status": $BOARD_HAS_TRIAGE_STATUS,
    "board_has_sort": $BOARD_HAS_SORT,
    "maria_santos": $MARIA_DATA,
    "james_wilson": $JAMES_DATA,
    "aisha_patel": $AISHA_DATA,
    "gui_save_detected": $GUI_SAVE_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/triage_result.json"

echo "Result saved to /tmp/triage_result.json"
cat /tmp/triage_result.json
echo "=== Export complete ==="
