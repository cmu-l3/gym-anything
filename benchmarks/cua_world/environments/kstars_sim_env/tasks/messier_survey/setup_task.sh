#!/bin/bash
echo "=== Setting up messier_survey task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Ensure INDI server is running with all simulators ─────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 2. Unpark telescope ──────────────────────────────────────────────
unpark_telescope
sleep 1

# ── 3. Configure CCD for local captures ──────────────────────────────
mkdir -p /home/ga/Images/survey
chown ga:ga /home/ga/Images/survey
set_ccd_upload_dir "/home/ga/Images/survey"

# ── 4. Record initial state for verification ─────────────────────────
INITIAL_FITS_COUNT=$(find /home/ga/Images -name "*.fits" 2>/dev/null | wc -l)
echo "$INITIAL_FITS_COUNT" > /tmp/initial_fits_count
echo "Initial FITS count: $INITIAL_FITS_COUNT"

# ── 5. Copy target catalog to Desktop for agent reference ────────────
cp /workspace/data/messier_targets.json /home/ga/Desktop/messier_targets.json
chown ga:ga /home/ga/Desktop/messier_targets.json

# ── 6. Ensure KStars is running and visible ──────────────────────────
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

# ── 7. Take screenshot of initial state ──────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see KStars planetarium."
echo "Task: Image 5 Messier objects using telescope slew + ~/capture_sky_view.sh for each."
echo "Target catalog available at ~/Desktop/messier_targets.json"
