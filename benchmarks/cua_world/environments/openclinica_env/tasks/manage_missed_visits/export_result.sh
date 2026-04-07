#!/bin/bash
echo "=== Exporting manage_missed_visits result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Resolve IDs
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
SED_BASE=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
SED_WK4=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")

SS_101=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
SS_102=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-102' AND study_id = $DM_STUDY_ID LIMIT 1")
SS_103=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")

# 2. Get Event Statuses (5=Stopped, 6=Skipped)
DM101_STATUS=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $SS_101 AND study_event_definition_id = $SED_WK4 ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null)
DM102_STATUS=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $SS_102 AND study_event_definition_id = $SED_BASE ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null)
DM103_STATUS=$(oc_query "SELECT subject_event_status_id FROM study_event WHERE study_subject_id = $SS_103 AND study_event_definition_id = $SED_WK4 ORDER BY study_event_id DESC LIMIT 1" 2>/dev/null)

# 3. Get Discrepancy Note Counts matching keywords
NOTE_COVID=$(oc_query "SELECT COUNT(*) FROM discrepancy_note WHERE LOWER(description) LIKE '%covid%' OR LOWER(detailed_notes) LIKE '%covid%'" 2>/dev/null)
NOTE_TRANS=$(oc_query "SELECT COUNT(*) FROM discrepancy_note WHERE LOWER(description) LIKE '%transportation%' OR LOWER(detailed_notes) LIKE '%transportation%'" 2>/dev/null)
NOTE_WITHDREW=$(oc_query "SELECT COUNT(*) FROM discrepancy_note WHERE LOWER(description) LIKE '%withdrew%' OR LOWER(detailed_notes) LIKE '%withdrew%'" 2>/dev/null)

# 4. Get Audit Log Count
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/manage_missed_visits_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm101_status_id": ${DM101_STATUS:-1},
    "dm102_status_id": ${DM102_STATUS:-1},
    "dm103_status_id": ${DM103_STATUS:-1},
    "note_covid_count": ${NOTE_COVID:-0},
    "note_transportation_count": ${NOTE_TRANS:-0},
    "note_withdrew_count": ${NOTE_WITHDREW:-0},
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "result_nonce": "$NONCE"
}
EOF

# Handle permissions safely
rm -f /tmp/manage_missed_visits_result.json 2>/dev/null || sudo rm -f /tmp/manage_missed_visits_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/manage_missed_visits_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/manage_missed_visits_result.json
chmod 666 /tmp/manage_missed_visits_result.json 2>/dev/null || sudo chmod 666 /tmp/manage_missed_visits_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/manage_missed_visits_result.json"