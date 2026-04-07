#!/bin/bash
echo "=== Exporting consolidate_duplicate_enrollment result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Query for study ID
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

# 1. Fetch DM-205 Status (Should be Removed - e.g. 3, 4, 5)
DM205_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE label = 'DM-205' AND study_id = $DM_STUDY_ID LIMIT 1")

# 2. Fetch DM-204 Secondary ID
DM204_DATA=$(oc_query "SELECT study_subject_id, secondary_label FROM study_subject WHERE label = 'DM-204' AND study_id = $DM_STUDY_ID LIMIT 1")
DM204_SS_ID=$(echo "$DM204_DATA" | cut -d'|' -f1)
DM204_SEC_ID=$(echo "$DM204_DATA" | cut -d'|' -f2)

# 3. Fetch DM-204 Baseline Event Date
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID AND status_id != 3 LIMIT 1")
DM204_EVENT_DATE=""
if [ -n "$DM204_SS_ID" ] && [ -n "$BASELINE_SED_ID" ]; then
    DM204_EVENT_DATE=$(oc_query "SELECT start_date FROM study_event WHERE study_subject_id = $DM204_SS_ID AND study_event_definition_id = $BASELINE_SED_ID ORDER BY study_event_id DESC LIMIT 1")
fi

# Fetch Audit Logs for anti-gaming checks
AUDIT_LOG_COUNT=$(docker exec oc-postgres psql -U clinica openclinica -tAc "SELECT COUNT(*) FROM audit_log_event" 2>/dev/null || echo "0")
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
RESULT_NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Formulate JSON 
TEMP_JSON=$(mktemp /tmp/consolidate_duplicate_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm205_status_id": ${DM205_STATUS:-0},
    "dm204_secondary_id": "$(json_escape "${DM204_SEC_ID:-}")",
    "dm204_event_date": "$(json_escape "${DM204_EVENT_DATE:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$RESULT_NONCE"
}
EOF

# Avoid permissions issues moving back out
rm -f /tmp/consolidate_duplicate_result.json 2>/dev/null || sudo rm -f /tmp/consolidate_duplicate_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/consolidate_duplicate_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/consolidate_duplicate_result.json
chmod 666 /tmp/consolidate_duplicate_result.json 2>/dev/null || sudo chmod 666 /tmp/consolidate_duplicate_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/consolidate_duplicate_result.json"
cat /tmp/consolidate_duplicate_result.json
echo "=== Export Complete ==="