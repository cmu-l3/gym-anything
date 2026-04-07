#!/bin/bash
echo "=== Exporting schedule_event_for_subject result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Get IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
SCR_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Screening Visit' AND study_id = $DM_STUDY_ID LIMIT 1")
SS101_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'SS_101' AND study_id = $DM_STUDY_ID LIMIT 1")

# 2. Check for the event on SS_101
EVENT_FOUND="false"
EVENT_DATE=""
EVENT_LOCATION=""
EVENT_STATUS_ID="0"
EVENT_CREATED_TIME="0"

if [ -n "$SS101_ID" ] && [ -n "$SCR_SED_ID" ]; then
    # Query the event data, pulling the exact values the agent entered
    EVENT_DATA=$(oc_query "SELECT start_date, location, subject_event_status_id, CAST(EXTRACT(EPOCH FROM date_created) AS INTEGER) FROM study_event WHERE study_subject_id = $SS101_ID AND study_event_definition_id = $SCR_SED_ID ORDER BY study_event_id DESC LIMIT 1")
    
    if [ -n "$EVENT_DATA" ]; then
        EVENT_FOUND="true"
        EVENT_DATE=$(echo "$EVENT_DATA" | cut -d'|' -f1)
        EVENT_LOCATION=$(echo "$EVENT_DATA" | cut -d'|' -f2)
        EVENT_STATUS_ID=$(echo "$EVENT_DATA" | cut -d'|' -f3)
        EVENT_CREATED_TIME=$(echo "$EVENT_DATA" | cut -d'|' -f4)
    fi
fi

# 3. Check that control subjects SS_102 and SS_103 remain untouched
SS102_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'SS_102' AND study_id = $DM_STUDY_ID LIMIT 1")
SS103_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'SS_103' AND study_id = $DM_STUDY_ID LIMIT 1")

SS102_EVENT_COUNT="0"
SS103_EVENT_COUNT="0"

if [ -n "$SS102_ID" ]; then
    SS102_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $SS102_ID")
fi
if [ -n "$SS103_ID" ]; then
    SS103_EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $SS103_ID")
fi

# 4. Generate JSON Output
TEMP_JSON=$(mktemp /tmp/schedule_event_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "event_found": $EVENT_FOUND,
    "event_date": "$(json_escape "${EVENT_DATE:-}")",
    "event_location": "$(json_escape "${EVENT_LOCATION:-}")",
    "event_status_id": ${EVENT_STATUS_ID:-0},
    "event_created_time": ${EVENT_CREATED_TIME:-0},
    "ss102_event_count": ${SS102_EVENT_COUNT:-0},
    "ss103_event_count": ${SS103_EVENT_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")",
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Safely copy to destination
rm -f /tmp/schedule_event_result.json 2>/dev/null || sudo rm -f /tmp/schedule_event_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/schedule_event_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/schedule_event_result.json
chmod 666 /tmp/schedule_event_result.json 2>/dev/null || sudo chmod 666 /tmp/schedule_event_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/schedule_event_result.json"
cat /tmp/schedule_event_result.json