#!/bin/bash
echo "=== Exporting study_closeout result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# --- Get study IDs ---
DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
AP_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' AND status_id != 3 LIMIT 1")

# If status_id=3 filtering removes them (edge case where study was deleted), try without filter
if [ -z "$DM_STUDY_ID" ]; then
    DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
fi
if [ -z "$AP_STUDY_ID" ]; then
    AP_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' LIMIT 1")
fi

echo "DM Trial study_id: $DM_STUDY_ID"
echo "AP Pilot study_id: $AP_STUDY_ID"

# --- Criterion 1: Check if "End of Study Assessment" event def exists in DM Trial ---
EOS_COUNT="0"
EOS_NAME=""
EOS_TYPE=""
EOS_REPEATING=""
EOS_DESCRIPTION=""

if [ -n "$DM_STUDY_ID" ]; then
    # Broad match: end+assess OR end+study OR final+assess
    EOS_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND status_id != 3 AND (LOWER(name) LIKE '%end%assess%' OR (LOWER(name) LIKE '%end%' AND LOWER(name) LIKE '%study%') OR LOWER(name) LIKE '%final%assess%')")

    if [ "${EOS_COUNT:-0}" != "0" ] && [ -n "$EOS_COUNT" ]; then
        EOS_ROW=$(oc_query "SELECT name, type, repeating::text, description FROM study_event_definition WHERE study_id = $DM_STUDY_ID AND status_id != 3 AND (LOWER(name) LIKE '%end%assess%' OR (LOWER(name) LIKE '%end%' AND LOWER(name) LIKE '%study%') OR LOWER(name) LIKE '%final%assess%') ORDER BY study_event_definition_id DESC LIMIT 1")
        EOS_NAME=$(echo "$EOS_ROW" | cut -d'|' -f1)
        EOS_TYPE=$(echo "$EOS_ROW" | cut -d'|' -f2)
        EOS_REPEATING=$(echo "$EOS_ROW" | cut -d'|' -f3)
        EOS_DESCRIPTION=$(echo "$EOS_ROW" | cut -d'|' -f4)
    fi
fi

echo "End of Study Assessment event def: count=$EOS_COUNT, name='$EOS_NAME', type='$EOS_TYPE', repeating=$EOS_REPEATING"

EOS_EXISTS="false"
if [ "${EOS_COUNT:-0}" != "0" ] && [ -n "$EOS_COUNT" ] && [ "$EOS_COUNT" -gt 0 ] 2>/dev/null; then
    EOS_EXISTS="true"
fi

# --- Criterion 2: Get DM-103's current status in study_subject ---
DM103_STATUS="1"
DM103_SS_ID=""
if [ -n "$DM_STUDY_ID" ]; then
    DM103_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")
    if [ -n "$DM103_SS_ID" ]; then
        DM103_STATUS=$(oc_query "SELECT status_id FROM study_subject WHERE study_subject_id = $DM103_SS_ID LIMIT 1")
    fi
fi
echo "DM-103 study_subject status_id: $DM103_STATUS"

# --- Criterion 3: Get DM Trial's current status_id ---
DM_TRIAL_STATUS="1"
if [ -n "$DM_STUDY_ID" ]; then
    DM_TRIAL_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $DM_STUDY_ID LIMIT 1")
fi
echo "DM Trial current status_id: $DM_TRIAL_STATUS"

# --- Criterion 4: Get AP Pilot's current status_id ---
AP_PILOT_STATUS="4"
if [ -n "$AP_STUDY_ID" ]; then
    AP_PILOT_STATUS=$(oc_query "SELECT status_id FROM study WHERE study_id = $AP_STUDY_ID LIMIT 1")
fi
echo "AP Pilot current status_id: $AP_PILOT_STATUS"

# --- Criterion 5: Check for export files newer than task start ---
EXPORT_FILE=$(find /home/ga/Desktop /home/ga/Downloads -newer /tmp/task_start_timestamp -type f \( \
    -name "*.xml" -o -name "*.zip" -o -name "*.xls" -o \
    -name "*.xlsx" -o -name "*.csv" -o -name "*.ods" \
\) 2>/dev/null | head -1)

EXPORT_EXISTS="false"
EXPORT_PATH=""
if [ -n "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_PATH="$EXPORT_FILE"
fi
echo "Export file found: $EXPORT_EXISTS (path: $EXPORT_PATH)"

# --- Read baseline values for comparison ---
BASELINE_DM_STATUS=$(cat /tmp/baseline_dm_trial_status 2>/dev/null || echo "1")
BASELINE_AP_STATUS=$(cat /tmp/baseline_ap_pilot_status 2>/dev/null || echo "4")
BASELINE_EVENT_DEF_COUNT=$(cat /tmp/baseline_dm_trial_event_def_count 2>/dev/null || echo "0")
BASELINE_DM103_STATUS=$(cat /tmp/baseline_dm103_status 2>/dev/null || echo "1")

# --- Audit log ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

echo "Audit log count: $AUDIT_LOG_COUNT (baseline: $AUDIT_BASELINE_COUNT)"

# --- Write result JSON ---
TEMP_JSON=$(mktemp /tmp/study_closeout_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "eos_event_def_exists": $EOS_EXISTS,
    "eos_event_def_count": ${EOS_COUNT:-0},
    "eos_event_def_name": "$(json_escape "${EOS_NAME:-}")",
    "eos_event_def_type": "$(json_escape "${EOS_TYPE:-}")",
    "eos_event_def_repeating": "$(json_escape "${EOS_REPEATING:-}")",
    "eos_event_def_description": "$(json_escape "${EOS_DESCRIPTION:-}")",
    "dm103_status_id": ${DM103_STATUS:-1},
    "dm_trial_status_id": ${DM_TRIAL_STATUS:-1},
    "ap_pilot_status_id": ${AP_PILOT_STATUS:-4},
    "export_file_exists": $EXPORT_EXISTS,
    "export_file_path": "$(json_escape "${EXPORT_PATH:-}")",
    "baseline_dm_trial_status": ${BASELINE_DM_STATUS:-1},
    "baseline_ap_pilot_status": ${BASELINE_AP_STATUS:-4},
    "baseline_event_def_count": ${BASELINE_EVENT_DEF_COUNT:-0},
    "baseline_dm103_status": ${BASELINE_DM103_STATUS:-1},
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/study_closeout_result.json"

echo "=== Export complete ==="
echo "Summary:"
echo "  EOS event def exists: $EOS_EXISTS"
echo "  DM-103 status: $DM103_STATUS (baseline: $BASELINE_DM103_STATUS)"
echo "  DM Trial status: $DM_TRIAL_STATUS (baseline: $BASELINE_DM_STATUS)"
echo "  AP Pilot status: $AP_PILOT_STATUS (baseline: $BASELINE_AP_STATUS)"
echo "  Export file: $EXPORT_EXISTS"
