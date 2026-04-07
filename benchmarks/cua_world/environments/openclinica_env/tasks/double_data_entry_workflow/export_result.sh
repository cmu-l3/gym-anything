#!/bin/bash
echo "=== Exporting double_data_entry_workflow result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

# --- 1. Check if CRF Exists ---
CRF_DATA=$(oc_query "SELECT crf_id, name FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' AND status_id != 3 LIMIT 1")
CRF_EXISTS="false"
CRF_ID=""
CRF_NAME=""

if [ -n "$CRF_DATA" ]; then
    CRF_EXISTS="true"
    CRF_ID=$(echo "$CRF_DATA" | cut -d'|' -f1)
    CRF_NAME=$(echo "$CRF_DATA" | cut -d'|' -f2)
else
    # Fallback to partial match
    CRF_DATA=$(oc_query "SELECT crf_id, name FROM crf WHERE LOWER(name) LIKE '%vital%' AND status_id != 3 ORDER BY crf_id DESC LIMIT 1")
    if [ -n "$CRF_DATA" ]; then
        CRF_EXISTS="true"
        CRF_ID=$(echo "$CRF_DATA" | cut -d'|' -f1)
        CRF_NAME=$(echo "$CRF_DATA" | cut -d'|' -f2)
    fi
fi
echo "CRF Found: $CRF_EXISTS (ID=$CRF_ID)"

# --- 2. Check Event Definition CRF matrix (DDE Flag) ---
DDE_ENABLED="false"
if [ -n "$CRF_ID" ]; then
    # PostgreSQL boolean is returned as 't' or 'f'
    DDE_FLAG=$(oc_query "SELECT edc.double_entry FROM event_definition_crf edc JOIN study_event_definition sed ON edc.study_event_definition_id = sed.study_event_definition_id WHERE sed.name = 'Baseline Assessment' AND edc.crf_id = $CRF_ID LIMIT 1")
    if [ -z "$DDE_FLAG" ]; then
        # Try via crf_version joining
        DDE_FLAG=$(oc_query "SELECT edc.double_entry FROM event_definition_crf edc JOIN crf_version cv ON edc.crf_version_id = cv.crf_version_id JOIN study_event_definition sed ON edc.study_event_definition_id = sed.study_event_definition_id WHERE sed.name = 'Baseline Assessment' AND cv.crf_id = $CRF_ID LIMIT 1")
    fi
    
    if [ "$DDE_FLAG" = "t" ] || [ "$DDE_FLAG" = "true" ] || [ "$DDE_FLAG" = "1" ]; then
        DDE_ENABLED="true"
    fi
fi
echo "DDE Enabled: $DDE_ENABLED ($DDE_FLAG)"

# --- 3. Check Study Event Scheduled ---
DM101_SS_ID=$(oc_query "SELECT study_subject_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
BASELINE_SED_ID=$(oc_query "SELECT study_event_definition_id FROM study_event_definition WHERE name = 'Baseline Assessment' AND study_id = $DM_STUDY_ID LIMIT 1")

EVENT_SCHEDULED="false"
if [ -n "$DM101_SS_ID" ] && [ -n "$BASELINE_SED_ID" ]; then
    EVENT_COUNT=$(oc_query "SELECT COUNT(*) FROM study_event WHERE study_subject_id = $DM101_SS_ID AND study_event_definition_id = $BASELINE_SED_ID")
    if [ "$EVENT_COUNT" -gt 0 ] 2>/dev/null; then
        EVENT_SCHEDULED="true"
    fi
fi
echo "Event Scheduled: $EVENT_SCHEDULED"

# --- 4. Check Event CRF (Data Entry Status & Users) ---
EVENT_CRF_ID=""
STATUS_ID="0"
OWNER_NAME=""
UPDATER_NAME=""
VALUES_LIST=""

if [ "$EVENT_SCHEDULED" = "true" ] && [ -n "$CRF_ID" ]; then
    # Fetch the event_crf data
    EC_DATA=$(oc_query "SELECT ec.event_crf_id, ec.status_id, u1.user_name as owner, u2.user_name as updater 
                        FROM event_crf ec 
                        JOIN study_event se ON ec.study_event_id = se.study_event_id 
                        LEFT JOIN user_account u1 ON ec.owner_id = u1.user_id 
                        LEFT JOIN user_account u2 ON ec.update_id = u2.user_id 
                        JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id 
                        WHERE se.study_subject_id = $DM101_SS_ID AND cv.crf_id = $CRF_ID 
                        ORDER BY ec.event_crf_id DESC LIMIT 1")
    if [ -n "$EC_DATA" ]; then
        EVENT_CRF_ID=$(echo "$EC_DATA" | cut -d'|' -f1)
        STATUS_ID=$(echo "$EC_DATA" | cut -d'|' -f2)
        OWNER_NAME=$(echo "$EC_DATA" | cut -d'|' -f3)
        UPDATER_NAME=$(echo "$EC_DATA" | cut -d'|' -f4)
        
        # Fetch item data values safely concatenated
        VALUES_LIST=$(oc_query "SELECT value FROM item_data WHERE event_crf_id = $EVENT_CRF_ID" | tr '\n' ',' | sed 's/,$//')
    fi
fi
echo "Event CRF: ID=$EVENT_CRF_ID, Status=$STATUS_ID, Owner=$OWNER_NAME, Updater=$UPDATER_NAME"
echo "Values: $VALUES_LIST"

# --- 5. Audits ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Read Nonce
RESULT_NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# --- 6. Write JSON ---
TEMP_JSON=$(mktemp /tmp/dde_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "crf_exists": $CRF_EXISTS,
    "crf_name": "$(json_escape "${CRF_NAME:-}")",
    "dde_enabled": $DDE_ENABLED,
    "event_scheduled": $EVENT_SCHEDULED,
    "event_crf_id": "${EVENT_CRF_ID:-}",
    "status_id": ${STATUS_ID:-0},
    "owner_name": "$(json_escape "${OWNER_NAME:-}")",
    "updater_name": "$(json_escape "${UPDATER_NAME:-}")",
    "item_values": "$(json_escape "${VALUES_LIST:-}")",
    "audit_baseline": ${AUDIT_BASELINE_COUNT:-0},
    "audit_current": ${AUDIT_LOG_COUNT:-0},
    "result_nonce": "$RESULT_NONCE"
}
EOF

# Safe file move
rm -f /tmp/double_data_entry_result.json 2>/dev/null || sudo rm -f /tmp/double_data_entry_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/double_data_entry_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/double_data_entry_result.json
chmod 666 /tmp/double_data_entry_result.json 2>/dev/null || sudo chmod 666 /tmp/double_data_entry_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "JSON saved to /tmp/double_data_entry_result.json"
echo "=== Export Complete ==="