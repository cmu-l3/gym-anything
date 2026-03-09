#!/bin/bash
echo "=== Setting up manage_user_roles task ==="

source /workspace/scripts/task_utils.sh

# ── Study ID resolution ────────────────────────────────────────────────────────

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")
if [ -z "$DM_STUDY_ID" ]; then
    echo "ERROR: Phase II Diabetes Trial (DM-TRIAL-2024) not found"
    exit 1
fi
echo "DM Trial study_id: $DM_STUDY_ID"

CV_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'CV-REG-2023' AND status_id != 3 LIMIT 1")
if [ -z "$CV_STUDY_ID" ]; then
    echo "ERROR: Cardiovascular Outcomes Registry (CV-REG-2023) not found"
    exit 1
fi
echo "CV Registry study_id: $CV_STUDY_ID"

AP_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'AP-PILOT-2022' AND status_id != 3 LIMIT 1")
if [ -z "$AP_STUDY_ID" ]; then
    echo "ERROR: Asthma Prevention Pilot (AP-PILOT-2022) not found"
    exit 1
fi
echo "AP Pilot study_id: $AP_STUDY_ID"

# Save study IDs for export script
echo "$DM_STUDY_ID" > /tmp/dm_study_id
echo "$CV_STUDY_ID" > /tmp/cv_study_id
echo "$AP_STUDY_ID" > /tmp/ap_study_id

# ── Ensure mrivera exists in user_account ─────────────────────────────────────

MRIVERA_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'mrivera'" 2>/dev/null || echo "0")
if [ "${MRIVERA_EXISTS:-0}" = "0" ]; then
    echo "Creating mrivera user account..."
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created, institutional_affiliation)
              VALUES ('mrivera', 'da39a3ee5e6b4b0d3255bfef95601890afd80709', 'Maria', 'Rivera', 'mrivera@clinical.org', 1, 1, NOW(), 'City Hospital')" 2>/dev/null || true
fi

# ── Ensure lchang exists in user_account ──────────────────────────────────────

LCHANG_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'lchang'" 2>/dev/null || echo "0")
if [ "${LCHANG_EXISTS:-0}" = "0" ]; then
    echo "Creating lchang user account..."
    oc_query "INSERT INTO user_account (user_name, passwd, first_name, last_name, email, status_id, owner_id, date_created, institutional_affiliation)
              VALUES ('lchang', 'da39a3ee5e6b4b0d3255bfef95601890afd80709', 'Lisa', 'Chang', 'lchang@clinical.org', 1, 1, NOW(), 'Metro Medical')" 2>/dev/null || true
fi

# ── Set up mrivera role in DM Trial (data_manager — agent must change to monitor) ──

echo "Setting mrivera to data_manager role in DM Trial..."
oc_query "DELETE FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $DM_STUDY_ID" 2>/dev/null || true
oc_query "INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, user_name)
          VALUES ('data_manager', $DM_STUDY_ID, 1, 1, NOW(), 'mrivera')" 2>/dev/null || true
echo "mrivera now has data_manager role in DM Trial"

# ── Set up lchang role in CV Registry (monitor — agent must remove it) ────────

echo "Setting lchang to monitor role in CV Registry..."
oc_query "DELETE FROM study_user_role WHERE user_name = 'lchang' AND study_id = $CV_STUDY_ID" 2>/dev/null || true
oc_query "INSERT INTO study_user_role (role_name, study_id, status_id, owner_id, date_created, user_name)
          VALUES ('monitor', $CV_STUDY_ID, 1, 1, NOW(), 'lchang')" 2>/dev/null || true
echo "lchang now has monitor role in CV Registry"

# ── Remove kpatel if already exists (clean state for user creation subtask) ───

KPATEL_EXISTS=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'kpatel'" 2>/dev/null || echo "0")
if [ "${KPATEL_EXISTS:-0}" != "0" ]; then
    echo "Removing pre-existing kpatel account for clean state..."
    oc_query "DELETE FROM study_user_role WHERE user_name = 'kpatel'" 2>/dev/null || true
    oc_query "DELETE FROM user_account WHERE user_name = 'kpatel'" 2>/dev/null || true
fi
echo "kpatel: clean state confirmed"

# ── Remove mrivera's AP Pilot role if it exists (clean state) ─────────────────

oc_query "DELETE FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $AP_STUDY_ID" 2>/dev/null || true
echo "mrivera AP Pilot role: clean state confirmed"

# ── Record baseline state ──────────────────────────────────────────────────────

MRIVERA_DM_ROLE=$(oc_query "SELECT role_name FROM study_user_role WHERE user_name = 'mrivera' AND study_id = $DM_STUDY_ID AND status_id = 1 LIMIT 1" 2>/dev/null || echo "")
echo "${MRIVERA_DM_ROLE:-data_manager}" > /tmp/baseline_mrivera_dm_role
echo "Baseline mrivera DM role: ${MRIVERA_DM_ROLE:-data_manager}"

LCHANG_CV_ROLE_COUNT=$(oc_query "SELECT COUNT(*) FROM study_user_role WHERE user_name = 'lchang' AND study_id = $CV_STUDY_ID AND status_id = 1" 2>/dev/null || echo "0")
echo "${LCHANG_CV_ROLE_COUNT:-0}" > /tmp/baseline_lchang_cv_role_count
echo "Baseline lchang CV active role count: ${LCHANG_CV_ROLE_COUNT:-0}"

KPATEL_COUNT=$(oc_query "SELECT COUNT(*) FROM user_account WHERE user_name = 'kpatel'" 2>/dev/null || echo "0")
echo "${KPATEL_COUNT:-0}" > /tmp/baseline_kpatel_exists
echo "Baseline kpatel exists count: ${KPATEL_COUNT:-0}"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded"

# ── Ensure Firefox running and logged in ──────────────────────────────────────

if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30

ensure_logged_in

# Switch active study to DM Trial (most relevant for first subtask)
switch_active_study "DM-TRIAL-2024"

focus_firefox
sleep 1

DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 0.5
focus_firefox

# ── Record audit baseline AFTER all setup navigation ─────────────────────────

AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

# ── Generate integrity nonce ──────────────────────────────────────────────────

NONCE=$(generate_result_nonce)
echo "Result integrity nonce: $NONCE"

take_screenshot /tmp/task_start_screenshot.png

echo "=== manage_user_roles task setup complete ==="
echo "Summary of initial state:"
echo "  mrivera DM Trial role  : ${MRIVERA_DM_ROLE:-data_manager} (agent must change to 'monitor')"
echo "  lchang CV Registry roles: ${LCHANG_CV_ROLE_COUNT:-1} active (agent must remove)"
echo "  kpatel user exists     : false (agent must create)"
echo "  mrivera AP Pilot role  : none (agent must assign 'monitor')"
