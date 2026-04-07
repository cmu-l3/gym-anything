#!/bin/bash
echo "=== Exporting admin_recovery result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# --- Retrieve IDs ---
DM_STUDY_ID=$(cat /tmp/dm_study_id 2>/dev/null || oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' LIMIT 1")
CV_STUDY_ID=$(cat /tmp/cv_study_id 2>/dev/null || oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' LIMIT 1")

# --- 1. Check mrivera unlocked status ---
MRIVERA_DATA=$(oc_query "SELECT account_non_locked, status_id FROM user_account WHERE user_name = 'mrivera' LIMIT 1")
MRIVERA_UNLOCKED="false"
MRIVERA_STATUS_ID="0"

if [ -n "$MRIVERA_DATA" ]; then
    ACCOUNT_NON_LOCKED=$(echo "$MRIVERA_DATA" | cut -d'|' -f1)
    MRIVERA_STATUS_ID=$(echo "$MRIVERA_DATA" | cut -d'|' -f2)
    if [ "$ACCOUNT_NON_LOCKED" = "t" ]; then
        MRIVERA_UNLOCKED="true"
    fi
fi
echo "mrivera: unlocked=$MRIVERA_UNLOCKED, status_id=$MRIVERA_STATUS_ID"

# --- 2. Check DM-101 and DM-103 status ---
DM101_STATUS_ID=$(oc_query "SELECT status_id FROM study_subject WHERE label = 'DM-101' AND study_id = $DM_STUDY_ID LIMIT 1")
DM103_STATUS_ID=$(oc_query "SELECT status_id FROM study_subject WHERE label = 'DM-103' AND study_id = $DM_STUDY_ID LIMIT 1")

echo "DM-101 status_id: ${DM101_STATUS_ID:-not found}"
echo "DM-103 status_id: ${DM103_STATUS_ID:-not found}"

# --- 3. Check mrivera role in CV-REG-2023 ---
CV_ROLE_DATA=$(oc_query "SELECT role_name, status_id FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $CV_STUDY_ID AND status_id != 3 ORDER BY study_user_role_id DESC LIMIT 1")
CV_ROLE_NAME=""
CV_ROLE_STATUS_ID="0"

if [ -n "$CV_ROLE_DATA" ]; then
    CV_ROLE_NAME=$(echo "$CV_ROLE_DATA" | cut -d'|' -f1)
    CV_ROLE_STATUS_ID=$(echo "$CV_ROLE_DATA" | cut -d'|' -f2)
fi
echo "mrivera CV role: '$CV_ROLE_NAME', status_id=$CV_ROLE_STATUS_ID"

# --- 4. Audit Log Verification ---
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo "Audit log count: $AUDIT_LOG_COUNT (baseline: $AUDIT_BASELINE_COUNT)"

# --- Compile JSON ---
TEMP_JSON=$(mktemp /tmp/admin_recovery_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mrivera_unlocked": $MRIVERA_UNLOCKED,
    "mrivera_status_id": ${MRIVERA_STATUS_ID:-0},
    "dm101_status_id": ${DM101_STATUS_ID:-0},
    "dm103_status_id": ${DM103_STATUS_ID:-0},
    "cv_role_name": "$(json_escape "${CV_ROLE_NAME:-}")",
    "cv_role_status_id": ${CV_ROLE_STATUS_ID:-0},
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/admin_recovery_result.json 2>/dev/null || sudo rm -f /tmp/admin_recovery_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/admin_recovery_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/admin_recovery_result.json
chmod 666 /tmp/admin_recovery_result.json 2>/dev/null || sudo chmod 666 /tmp/admin_recovery_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/admin_recovery_result.json