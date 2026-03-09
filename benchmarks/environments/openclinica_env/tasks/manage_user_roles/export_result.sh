#!/bin/bash
echo "=== Exporting manage_user_roles result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# ── Study ID resolution ────────────────────────────────────────────────────────

DM_STUDY_ID=$(cat /tmp/dm_study_id 2>/dev/null || oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
CV_STUDY_ID=$(cat /tmp/cv_study_id 2>/dev/null || oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
AP_STUDY_ID=$(cat /tmp/ap_study_id 2>/dev/null || oc_query "SELECT study_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' AND status_id != 3 LIMIT 1")

echo "Study IDs: DM=$DM_STUDY_ID, CV=$CV_STUDY_ID, AP=$AP_STUDY_ID"

# ── Subtask 1: mrivera role in DM Trial ───────────────────────────────────────

echo ""
echo "=== Subtask 1: mrivera role in DM Trial ==="
MRIVERA_DM_DATA=$(oc_query "SELECT role_name, status_id FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $DM_STUDY_ID AND status_id = 1 ORDER BY study_user_role_id DESC LIMIT 1" 2>/dev/null || echo "")
MRIVERA_DM_ROLE=$(echo "$MRIVERA_DM_DATA" | cut -d'|' -f1)
MRIVERA_DM_STATUS=$(echo "$MRIVERA_DM_DATA" | cut -d'|' -f2)
echo "mrivera DM role: '${MRIVERA_DM_ROLE}' (status_id: ${MRIVERA_DM_STATUS})"

# Check if role is now 'monitor' (case-insensitive, allow partial match)
MRIVERA_DM_IS_MONITOR="false"
if echo "${MRIVERA_DM_ROLE}" | grep -qi "monitor"; then
    MRIVERA_DM_IS_MONITOR="true"
fi
echo "mrivera DM is_monitor: $MRIVERA_DM_IS_MONITOR"

# Also check all roles for mrivera in DM Trial (any status) for debug
echo "=== DEBUG: All mrivera DM Trial roles ==="
oc_query "SELECT role_name, status_id FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $DM_STUDY_ID" 2>/dev/null || true

# ── Subtask 2: lchang active roles in CV Registry ─────────────────────────────

echo ""
echo "=== Subtask 2: lchang active roles in CV Registry ==="
LCHANG_CV_ACTIVE_COUNT=$(oc_query "SELECT COUNT(*) FROM study_user_role WHERE user_name = 'lchang' AND study_id = $CV_STUDY_ID AND status_id = 1" 2>/dev/null || echo "0")
echo "lchang CV active role count: ${LCHANG_CV_ACTIVE_COUNT:-0}"

LCHANG_CV_REMOVED="false"
if [ "${LCHANG_CV_ACTIVE_COUNT:-0}" = "0" ]; then
    LCHANG_CV_REMOVED="true"
fi
echo "lchang CV access removed: $LCHANG_CV_REMOVED"

# Debug: all lchang CV roles
echo "=== DEBUG: All lchang CV Registry roles ==="
oc_query "SELECT role_name, status_id FROM study_user_role WHERE user_name = 'lchang' AND study_id = $CV_STUDY_ID" 2>/dev/null || true

# ── Subtask 3: kpatel user account exists ─────────────────────────────────────

echo ""
echo "=== Subtask 3: kpatel user account ==="
KPATEL_DATA=$(oc_query "SELECT user_id, first_name, last_name, email, institutional_affiliation, status_id FROM user_account WHERE user_name = 'kpatel' LIMIT 1" 2>/dev/null || echo "")
KPATEL_EXISTS="false"
KPATEL_USER_ID=""
KPATEL_FIRST=""
KPATEL_LAST=""
KPATEL_EMAIL=""
KPATEL_AFFILIATION=""
KPATEL_STATUS=""

if [ -n "$KPATEL_DATA" ]; then
    KPATEL_EXISTS="true"
    KPATEL_USER_ID=$(echo "$KPATEL_DATA" | cut -d'|' -f1)
    KPATEL_FIRST=$(echo "$KPATEL_DATA" | cut -d'|' -f2)
    KPATEL_LAST=$(echo "$KPATEL_DATA" | cut -d'|' -f3)
    KPATEL_EMAIL=$(echo "$KPATEL_DATA" | cut -d'|' -f4)
    KPATEL_AFFILIATION=$(echo "$KPATEL_DATA" | cut -d'|' -f5)
    KPATEL_STATUS=$(echo "$KPATEL_DATA" | cut -d'|' -f6)
    echo "kpatel found: id=$KPATEL_USER_ID, name=$KPATEL_FIRST $KPATEL_LAST"
    echo "  email=$KPATEL_EMAIL"
    echo "  affiliation=$KPATEL_AFFILIATION"
    echo "  status_id=$KPATEL_STATUS"
else
    echo "kpatel: NOT FOUND"
fi

# ── Subtask 4: kpatel role in DM Trial ───────────────────────────────────────

echo ""
echo "=== Subtask 4: kpatel role in DM Trial ==="
KPATEL_DM_DATA=$(oc_query "SELECT role_name, status_id FROM study_user_role WHERE user_name = 'kpatel' AND study_id = $DM_STUDY_ID AND status_id = 1 ORDER BY study_user_role_id DESC LIMIT 1" 2>/dev/null || echo "")
KPATEL_DM_ROLE=$(echo "$KPATEL_DM_DATA" | cut -d'|' -f1)
KPATEL_DM_STATUS=$(echo "$KPATEL_DM_DATA" | cut -d'|' -f2)
echo "kpatel DM role: '${KPATEL_DM_ROLE}' (status_id: ${KPATEL_DM_STATUS})"

KPATEL_IS_INVESTIGATOR="false"
if echo "${KPATEL_DM_ROLE}" | grep -qi "investigator"; then
    KPATEL_IS_INVESTIGATOR="true"
fi
echo "kpatel is_investigator in DM Trial: $KPATEL_IS_INVESTIGATOR"

# Debug: all kpatel roles
echo "=== DEBUG: All kpatel roles ==="
oc_query "SELECT role_name, study_id, status_id FROM study_user_role WHERE user_name = 'kpatel'" 2>/dev/null || true

# ── Subtask 5: mrivera role in AP Pilot ──────────────────────────────────────

echo ""
echo "=== Subtask 5: mrivera role in AP Pilot ==="
MRIVERA_AP_DATA=$(oc_query "SELECT role_name, status_id FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $AP_STUDY_ID AND status_id = 1 ORDER BY study_user_role_id DESC LIMIT 1" 2>/dev/null || echo "")
MRIVERA_AP_ROLE=$(echo "$MRIVERA_AP_DATA" | cut -d'|' -f1)
MRIVERA_AP_STATUS=$(echo "$MRIVERA_AP_DATA" | cut -d'|' -f2)
MRIVERA_AP_ACTIVE_COUNT=$(oc_query "SELECT COUNT(*) FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $AP_STUDY_ID AND status_id = 1" 2>/dev/null || echo "0")
echo "mrivera AP role: '${MRIVERA_AP_ROLE}' (status_id: ${MRIVERA_AP_STATUS})"
echo "mrivera AP active role count: ${MRIVERA_AP_ACTIVE_COUNT:-0}"

MRIVERA_AP_IS_MONITOR="false"
if echo "${MRIVERA_AP_ROLE}" | grep -qi "monitor"; then
    MRIVERA_AP_IS_MONITOR="true"
fi
echo "mrivera AP is_monitor: $MRIVERA_AP_IS_MONITOR"

# Debug: all mrivera roles across studies
echo "=== DEBUG: All mrivera roles ==="
oc_query "SELECT role_name, study_id, status_id FROM study_user_role WHERE user_name = 'mrivera'" 2>/dev/null || true

# ── Audit log counts ──────────────────────────────────────────────────────────

AUDIT_COUNT=$(get_recent_audit_count 15)
AUDIT_BASELINE=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
echo ""
echo "Audit: current=$AUDIT_COUNT, baseline=$AUDIT_BASELINE"

# ── JSON escape all strings ───────────────────────────────────────────────────

MRIVERA_DM_ROLE_ESC=$(json_escape "${MRIVERA_DM_ROLE}")
KPATEL_FIRST_ESC=$(json_escape "${KPATEL_FIRST}")
KPATEL_LAST_ESC=$(json_escape "${KPATEL_LAST}")
KPATEL_EMAIL_ESC=$(json_escape "${KPATEL_EMAIL}")
KPATEL_AFFILIATION_ESC=$(json_escape "${KPATEL_AFFILIATION}")
KPATEL_DM_ROLE_ESC=$(json_escape "${KPATEL_DM_ROLE}")
MRIVERA_AP_ROLE_ESC=$(json_escape "${MRIVERA_AP_ROLE}")

# ── Write result JSON ─────────────────────────────────────────────────────────

TEMP_JSON=$(mktemp /tmp/manage_user_roles_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "subtask1_mrivera_dm": {
        "role_name": "$MRIVERA_DM_ROLE_ESC",
        "status_id": "${MRIVERA_DM_STATUS:-}",
        "is_monitor": $MRIVERA_DM_IS_MONITOR
    },
    "subtask2_lchang_cv": {
        "active_role_count": ${LCHANG_CV_ACTIVE_COUNT:-0},
        "access_removed": $LCHANG_CV_REMOVED
    },
    "subtask3_kpatel_user": {
        "exists": $KPATEL_EXISTS,
        "user_id": "${KPATEL_USER_ID:-}",
        "first_name": "$KPATEL_FIRST_ESC",
        "last_name": "$KPATEL_LAST_ESC",
        "email": "$KPATEL_EMAIL_ESC",
        "institutional_affiliation": "$KPATEL_AFFILIATION_ESC",
        "status_id": "${KPATEL_STATUS:-}"
    },
    "subtask4_kpatel_dm_role": {
        "role_name": "$KPATEL_DM_ROLE_ESC",
        "status_id": "${KPATEL_DM_STATUS:-}",
        "is_investigator": $KPATEL_IS_INVESTIGATOR
    },
    "subtask5_mrivera_ap": {
        "role_name": "$MRIVERA_AP_ROLE_ESC",
        "status_id": "${MRIVERA_AP_STATUS:-}",
        "active_role_count": ${MRIVERA_AP_ACTIVE_COUNT:-0},
        "is_monitor": $MRIVERA_AP_IS_MONITOR
    },
    "audit_log_count": ${AUDIT_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE:-0},
    "result_nonce": "$(get_result_nonce)",
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" "/tmp/manage_user_roles_result.json"

echo ""
echo "=== Export complete ==="
echo "Result written to /tmp/manage_user_roles_result.json"
