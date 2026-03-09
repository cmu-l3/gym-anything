#!/bin/bash
echo "=== Setting up change_agency_scconfig task ==="

source /workspace/scripts/task_utils.sh

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Verify current agencyID ──────────────────────────────────────────────

echo "--- Verifying current agencyID ---"

CURRENT_AGENCY=$(grep -oP 'agencyID\s*=\s*\K\S+' "$SEISCOMP_ROOT/etc/global.cfg" 2>/dev/null || echo "unknown")
echo "Current agencyID: $CURRENT_AGENCY"

# Ensure agencyID is set to GYM (the initial value the agent must change)
if [ "$CURRENT_AGENCY" != "GYM" ]; then
    sed -i 's/^agencyID\s*=.*/agencyID = GYM/' "$SEISCOMP_ROOT/etc/global.cfg"
    echo "  Reset agencyID to GYM"
fi

echo "$CURRENT_AGENCY" > /tmp/initial_agency_id

# ─── 3. Kill any existing scconfig instances ──────────────────────────────────

echo "--- Preparing scconfig ---"
kill_seiscomp_gui scconfig

# ─── 4. Launch scconfig ──────────────────────────────────────────────────────

echo "--- Launching scconfig ---"
launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 3

# ─── 5. Dismiss any startup dialogs ──────────────────────────────────────────

dismiss_dialogs 2

# ─── 6. Focus and maximize scconfig window ────────────────────────────────────

focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"

sleep 2

# ─── 7. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/task_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig should be visible."
echo "Agent should navigate to Modules > global and change agencyID from 'GYM' to 'NIED'."
