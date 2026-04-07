#!/bin/bash
echo "=== Exporting duplicate_subject_reconciliation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Retrieve IDs
DM_STUDY_ID=$(cat /tmp/dm_study_id 2>/dev/null || echo "")
SS_105_ID=$(cat /tmp/dm105_ss_id 2>/dev/null || echo "")
SS_106_ID=$(cat /tmp/dm106_ss_id 2>/dev/null || echo "")
WK4_SED_ID=$(cat /tmp/wk4_sed_id 2>/dev/null || echo "")

# Fallbacks if files are missing
if [ -z "$DM_STUDY_ID" ]; then
    DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
fi
if [ -z "$SS_105_ID" ] && [ -n "$DM_STUDY_ID" ]; then
    SS_105_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-105' AND study_id = $DM_STUDY_ID LIMIT 1")
fi
if [ -z "$SS_106_ID" ] && [ -n "$DM_STUDY_ID" ]; then
    SS_106_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-106' AND study_id = $DM_STUDY_ID LIMIT 1")
fi
if [ -z "$WK4_SED_ID" ] && [ -n "$DM_STUDY_ID" ]; then
    WK4_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Week 4 Follow-up' AND study_id = $DM_STUDY_ID LIMIT 1")
fi

# Check Subject Statuses
DM106_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $SS_106_ID LIMIT 1" 2>/dev/null || echo "1")
DM105_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $SS_105_ID LIMIT 1" 2>/dev/null || echo "1")

# Check DM-105 Week 4 Event
DM105_WK4_EVENT_ID=""
if [ -n "$SS_105_ID" ] && [ -n "$WK4_SED_ID" ]; then
    DM105_WK4_EVENT_ID=$(oc_query "SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_105_ID AND study_event_definition_id = $WK4_SED_ID AND status_id != 3 LIMIT 1" 2>/dev/null || echo "")
fi

# Check CRF Status & Values
DM105_CRF_STATUS="0"
DM105_CRF_VALUES=""
if [ -n "$DM105_WK4_EVENT_ID" ]; then
    DM105_CRF_STATUS=$(oc_query "SELECT status_id FROM event_crf WHERE study_event_id = $DM105_WK4_EVENT_ID AND status_id != 3 ORDER BY event_crf_id DESC LIMIT 1" 2>/dev/null || echo "0")
    # Fetch transcribed values (comma-separated)
    DM105_CRF_VALUES=$(oc_query "SELECT value FROM item_data WHERE event_crf_id IN (SELECT event_crf_id FROM event_crf WHERE study_event_id = $DM105_WK4_EVENT_ID AND status_id != 3)" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
fi

# Fetch Audit and Integrity
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
RESULT_NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write JSON
TEMP_JSON=$(mktemp /tmp/duplicate_reconciliation_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dm106_status_id": ${DM106_STATUS:-1},
    "dm105_status_id": ${DM105_STATUS:-1},
    "dm105_wk4_event_exists": $([ -n "$DM105_WK4_EVENT_ID" ] && echo "true" || echo "false"),
    "dm105_crf_status_id": ${DM105_CRF_STATUS:-0},
    "dm105_crf_values": "$(json_escape "${DM105_CRF_VALUES:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$RESULT_NONCE"
}
EOF

rm -f /tmp/duplicate_reconciliation_result.json 2>/dev/null || sudo rm -f /tmp/duplicate_reconciliation_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/duplicate_reconciliation_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/duplicate_reconciliation_result.json
chmod 666 /tmp/duplicate_reconciliation_result.json 2>/dev/null || sudo chmod 666 /tmp/duplicate_reconciliation_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/duplicate_reconciliation_result.json"
cat /tmp/duplicate_reconciliation_result.json
echo "=== Export complete ==="