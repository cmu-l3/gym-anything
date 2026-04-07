#!/bin/bash
echo "=== Setting up e2e_study_activation task ==="

source /workspace/scripts/task_utils.sh

# =================================================================
# Phase 1: Clean up any pre-existing ONC-301 study and related data
# =================================================================

echo "Checking for pre-existing ONC-301 study..."
ONC_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'ONC-301' LIMIT 1" 2>/dev/null || echo "")

if [ -n "$ONC_STUDY_ID" ]; then
    echo "Found pre-existing ONC-301 (id=$ONC_STUDY_ID). Cleaning up..."

    # Find any sites under this study
    SITE_IDS=$(oc_query "SELECT study_id FROM study WHERE parent_study_id = $ONC_STUDY_ID" 2>/dev/null || echo "")

    # Clean up subjects, events, CRF data for both parent and sites
    for SID in $ONC_STUDY_ID $SITE_IDS; do
        if [ -n "$SID" ]; then
            # Get all study_subject_ids for this study/site
            SS_IDS=$(oc_query "SELECT study_subject_id FROM study_subject WHERE study_id = $SID" 2>/dev/null || echo "")
            for SS_ID in $SS_IDS; do
                if [ -n "$SS_ID" ]; then
                    # Delete item_data -> event_crf -> study_event cascade
                    oc_query "DELETE FROM item_data WHERE event_crf_id IN (
                        SELECT event_crf_id FROM event_crf WHERE study_event_id IN (
                            SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID
                        )
                    )" 2>/dev/null || true
                    oc_query "DELETE FROM event_crf WHERE study_event_id IN (
                        SELECT study_event_id FROM study_event WHERE study_subject_id = $SS_ID
                    )" 2>/dev/null || true
                    oc_query "DELETE FROM study_event WHERE study_subject_id = $SS_ID" 2>/dev/null || true

                    # Delete subject records
                    SUBJ_ID=$(oc_query "SELECT subject_id FROM study_subject WHERE study_subject_id = $SS_ID LIMIT 1" 2>/dev/null || echo "")
                    oc_query "DELETE FROM study_subject WHERE study_subject_id = $SS_ID" 2>/dev/null || true
                    if [ -n "$SUBJ_ID" ]; then
                        oc_query "DELETE FROM subject WHERE subject_id = $SUBJ_ID" 2>/dev/null || true
                    fi
                fi
            done
        fi
    done

    # Delete user roles for parent and sites
    oc_query "DELETE FROM study_user_role WHERE study_id = $ONC_STUDY_ID" 2>/dev/null || true
    for SID in $SITE_IDS; do
        if [ -n "$SID" ]; then
            oc_query "DELETE FROM study_user_role WHERE study_id = $SID" 2>/dev/null || true
        fi
    done

    # Delete event_definition_crf for this study
    oc_query "DELETE FROM event_definition_crf WHERE study_id = $ONC_STUDY_ID" 2>/dev/null || true

    # Delete event definitions
    oc_query "DELETE FROM study_event_definition WHERE study_id = $ONC_STUDY_ID" 2>/dev/null || true

    # Delete sites
    for SID in $SITE_IDS; do
        if [ -n "$SID" ]; then
            oc_query "DELETE FROM study WHERE study_id = $SID" 2>/dev/null || true
        fi
    done

    # Delete parent study
    oc_query "DELETE FROM study WHERE study_id = $ONC_STUDY_ID" 2>/dev/null || true

    echo "ONC-301 cleanup complete."
else
    echo "No pre-existing ONC-301 study found. Clean state."
fi

# =================================================================
# Phase 2: Clean up MRC-001 site if it exists standalone
# =================================================================
MRC_ORPHAN=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'MRC-001' LIMIT 1" 2>/dev/null || echo "")
if [ -n "$MRC_ORPHAN" ]; then
    echo "Removing orphan MRC-001 site..."
    oc_query "DELETE FROM study_user_role WHERE study_id = $MRC_ORPHAN" 2>/dev/null || true
    oc_query "DELETE FROM study WHERE study_id = $MRC_ORPHAN" 2>/dev/null || true
fi

# =================================================================
# Phase 3: Clean up Vital Signs CRF (may exist from other tasks)
# =================================================================
echo "Checking for existing Vital Signs CRF..."
EXISTING_CRF_ID=$(oc_query "SELECT crf_id FROM crf WHERE LOWER(TRIM(name)) = 'vital signs' LIMIT 1" 2>/dev/null || echo "")

if [ -n "$EXISTING_CRF_ID" ]; then
    echo "Found existing Vital Signs CRF (id=$EXISTING_CRF_ID). Removing for clean state..."

    # Cascade delete: item_data -> event_crf -> event_definition_crf -> item_form_metadata -> item_group_metadata -> items -> item_group -> crf_version -> crf
    oc_query "DELETE FROM item_data WHERE event_crf_id IN (
        SELECT ec.event_crf_id FROM event_crf ec
        JOIN crf_version cv ON ec.crf_version_id = cv.crf_version_id
        WHERE cv.crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true

    oc_query "DELETE FROM event_crf WHERE crf_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true

    oc_query "DELETE FROM event_definition_crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM event_definition_crf WHERE default_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true

    oc_query "DELETE FROM item_form_metadata WHERE crf_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true

    oc_query "DELETE FROM item_group_metadata WHERE crf_version_id IN (
        SELECT crf_version_id FROM crf_version WHERE crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true

    # Delete items that belong to item_groups of this CRF
    oc_query "DELETE FROM item WHERE item_id IN (
        SELECT i.item_id FROM item i
        JOIN item_group ig ON i.item_id = ig.item_id
        WHERE ig.crf_id = $EXISTING_CRF_ID
    )" 2>/dev/null || true

    oc_query "DELETE FROM item_group WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM crf_version WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true
    oc_query "DELETE FROM crf WHERE crf_id = $EXISTING_CRF_ID" 2>/dev/null || true

    echo "Vital Signs CRF cleanup complete."
else
    echo "No existing Vital Signs CRF. Clean state."
fi

# =================================================================
# Phase 4: Copy CRF template to user-accessible location
# =================================================================
if [ -f "/workspace/data/sample_crf.xls" ]; then
    cp /workspace/data/sample_crf.xls /home/ga/vital_signs_crf.xls
    chown ga:ga /home/ga/vital_signs_crf.xls
    chmod 644 /home/ga/vital_signs_crf.xls
    echo "CRF template copied to /home/ga/vital_signs_crf.xls"
else
    echo "WARNING: CRF template not found at /workspace/data/sample_crf.xls"
fi

# =================================================================
# Phase 5: Create source data verification document
# =================================================================
mkdir -p /home/ga/source_docs
chown ga:ga /home/ga/source_docs

cat > /home/ga/source_docs/ONC001_screening.txt << 'SOURCEEOF'
======================================================
        SOURCE DATA VERIFICATION FORM
======================================================

Study:    ONC-301 — Beacon NSCLC Phase III
Site:     Memorial Research Center (MRC-001)
Subject:  ONC-001
Visit:    Screening
Date:     01-Mar-2025

Recorded by: Dr. Sarah Chen, MD
------------------------------------------------------

VITAL SIGNS

  Systolic Blood Pressure:   142   mmHg
  Diastolic Blood Pressure:   88   mmHg
  Heart Rate:                  76   bpm
  Temperature:               37.1   C
  Respiratory Rate:            18   breaths/min
  Weight:                    81.4   kg
  Height:                   175.0   cm

------------------------------------------------------

CLINICAL NOTES:
  Patient is a 59-year-old male presenting with
  Stage IIIB non-small cell lung cancer (squamous).
  Controlled hypertension on lisinopril 10mg daily.
  BP elevated but within inclusion criteria (SBP < 160).
  ECOG performance status: 1.
  Eligible for randomization pending lab results.

======================================================
SOURCEEOF

chown ga:ga /home/ga/source_docs/ONC001_screening.txt
chmod 644 /home/ga/source_docs/ONC001_screening.txt
echo "Source document created at /home/ga/source_docs/ONC001_screening.txt"

# =================================================================
# Phase 5b: Ensure root password is usable without forced reset
# =================================================================
echo "Disabling forced password change on login..."
oc_query "UPDATE configuration SET value = '0' WHERE key = 'pwd.change.required'" 2>/dev/null || true
oc_query "UPDATE user_account SET passwd_timestamp = CURRENT_DATE + INTERVAL '365 days' WHERE user_name = 'root'" 2>/dev/null || true

# =================================================================
# Phase 5c: Fix Firefox Snap file picker permissions
# =================================================================
# On Ubuntu 22.04, Firefox is a Snap package even when installed via apt.
# The Snap sandbox blocks the native file picker from accessing /home/ga/.
# Fix: 1) Disable portal-based file picker in Firefox prefs
#      2) Copy CRF to Snap-accessible locations as fallback
#      3) Relaunch Firefox with DBUS_SESSION_BUS_ADDRESS set

echo "Fixing Firefox Snap file picker permissions..."

# Find and patch ALL Firefox profile directories (deb and snap paths)
for PROFILE_DIR in \
    /home/ga/.mozilla/firefox/default-release \
    /home/ga/snap/firefox/common/.mozilla/firefox/*.default* \
    /home/ga/snap/firefox/common/.mozilla/firefox/default-release; do
    if [ -d "$PROFILE_DIR" ] 2>/dev/null; then
        echo "Patching Firefox profile: $PROFILE_DIR"
        # Disable portal-based file picker (use GTK file picker instead)
        if ! grep -q 'use-xdg-desktop-portal' "$PROFILE_DIR/user.js" 2>/dev/null; then
            cat >> "$PROFILE_DIR/user.js" << 'FILEPICKERFIX'

// Fix file picker for Snap Firefox — use native GTK dialog instead of portal
user_pref("widget.use-xdg-desktop-portal.file-picker", 0);
user_pref("widget.use-xdg-desktop-portal.mime-handler", 0);
FILEPICKERFIX
            chown ga:ga "$PROFILE_DIR/user.js" 2>/dev/null || true
        fi
    fi
done

# Copy CRF template to multiple locations for file picker accessibility
for FALLBACK_DIR in /tmp /home/ga/Downloads /home/ga/snap/firefox/common/Downloads; do
    mkdir -p "$FALLBACK_DIR" 2>/dev/null || true
    cp /home/ga/vital_signs_crf.xls "$FALLBACK_DIR/vital_signs_crf.xls" 2>/dev/null || true
    chown ga:ga "$FALLBACK_DIR/vital_signs_crf.xls" 2>/dev/null || true
    chmod 644 "$FALLBACK_DIR/vital_signs_crf.xls" 2>/dev/null || true
done
echo "CRF template copied to fallback locations"

# Kill existing Firefox and relaunch with DBUS_SESSION_BUS_ADDRESS
echo "Restarting Firefox with D-Bus session for file picker access..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Ensure D-Bus session bus is available
if [ ! -S /run/user/1000/bus ]; then
    echo "D-Bus session bus not found, creating..."
    mkdir -p /run/user/1000
    chown ga:ga /run/user/1000
    chmod 700 /run/user/1000
    su - ga -c "dbus-launch --sh-syntax > /tmp/dbus_env.sh" 2>/dev/null || true
fi

# Launch Firefox with full environment for file picker access
setsid sudo -u ga bash -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus' firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &"
sleep 5

# =================================================================
# Phase 6: Delete stale output files BEFORE recording timestamp
# =================================================================
rm -f /tmp/e2e_study_activation_result.json 2>/dev/null || true
rm -f /tmp/task_end_screenshot.png 2>/dev/null || true

# =================================================================
# Phase 7: Record baselines
# =================================================================

# Record max study_id to detect new study creation
MAX_STUDY_ID=$(oc_query "SELECT COALESCE(MAX(study_id), 0) FROM study" 2>/dev/null || echo "0")
echo "$MAX_STUDY_ID" > /tmp/baseline_max_study_id
echo "Baseline max study_id: $MAX_STUDY_ID"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded"

# =================================================================
# Phase 8: Ensure Firefox is running and logged in
# =================================================================
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox (was not running)..."
    setsid sudo -u ga bash -c "DISPLAY=:1 DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/1000/bus' firefox 'http://localhost:8080/OpenClinica/MainMenu' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

wait_for_window "firefox\|mozilla\|OpenClinica" 30
ensure_logged_in
focus_firefox
sleep 1

# Click center to dismiss any overlays
DISPLAY=:1 xdotool mousemove 960 540 click 1 2>/dev/null || true
sleep 0.5
focus_firefox

# =================================================================
# Phase 9: Record audit baseline AFTER all setup navigation
# =================================================================
AUDIT_BASELINE=$(get_recent_audit_count 15)
echo "${AUDIT_BASELINE:-0}" > /tmp/audit_baseline_count
echo "Audit log baseline after setup: ${AUDIT_BASELINE:-0}"

# Generate integrity nonce
NONCE=$(generate_result_nonce)
echo "Result integrity nonce: $NONCE"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== e2e_study_activation task setup complete ==="
