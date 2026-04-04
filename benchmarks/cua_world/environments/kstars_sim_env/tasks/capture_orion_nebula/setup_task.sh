#!/bin/bash
echo "=== Setting up capture_orion_nebula task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Ensure INDI server is running with all simulators ─────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 2. Unpark telescope ──────────────────────────────────────────────
unpark_telescope
sleep 1

# ── 3. Configure CCD for local captures ──────────────────────────────
mkdir -p /home/ga/Images/sequences
chown ga:ga /home/ga/Images/sequences
set_ccd_upload_dir "/home/ga/Images/sequences"

# ── 4. Record initial state for verification ─────────────────────────
INITIAL_FITS_COUNT=$(find /home/ga/Images -name "*.fits" 2>/dev/null | wc -l)
echo "$INITIAL_FITS_COUNT" > /tmp/initial_fits_count
echo "Initial FITS count: $INITIAL_FITS_COUNT"

INITIAL_POS=$(get_telescope_position 2>/dev/null)
echo "$INITIAL_POS" > /tmp/initial_telescope_position

INITIAL_FILTER=$(indi_getprop -1 "Filter Simulator.FILTER_SLOT.FILTER_SLOT_VALUE" 2>/dev/null)
echo "$INITIAL_FILTER" > /tmp/initial_filter_slot

# ── 5. Ensure KStars is running and visible ──────────────────────────
ensure_kstars_running
sleep 3

# Dismiss any dialogs
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus
maximize_kstars
focus_kstars
sleep 1

# ── 6. Take screenshot of initial state ──────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see KStars planetarium."
echo "Task: Slew to M42, take multi-filter exposures, capture sky view with ~/capture_sky_view.sh"
