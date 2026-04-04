#!/bin/bash
echo "=== Setting up respond_transient_alert task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Ensure INDI server is running with all simulators ─────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 2. Unpark telescope so it's ready to slew ────────────────────────
unpark_telescope
sleep 1

# ── 3. Configure CCD to save captures locally ────────────────────────
mkdir -p /home/ga/Images/captures
chown ga:ga /home/ga/Images/captures
set_ccd_upload_dir "/home/ga/Images/captures"

# ── 4. Record initial state for verification ─────────────────────────
INITIAL_FITS_COUNT=$(find /home/ga/Images/captures -name "*.fits" 2>/dev/null | wc -l)
echo "$INITIAL_FITS_COUNT" > /tmp/initial_fits_count
echo "Initial FITS count: $INITIAL_FITS_COUNT"

INITIAL_POS=$(get_telescope_position 2>/dev/null)
echo "$INITIAL_POS" > /tmp/initial_telescope_position

# ── 5. Copy the transient alert file to the desktop for visibility ───
cp /workspace/data/transient_alert.json /home/ga/Desktop/ALERT_transient.json
chown ga:ga /home/ga/Desktop/ALERT_transient.json

# ── 6. Ensure KStars is running and visible ──────────────────────────
ensure_kstars_running
sleep 3

# Dismiss any lingering dialogs
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

# Maximize and focus KStars
maximize_kstars
focus_kstars
sleep 1

# ── 7. Take screenshot of initial state ──────────────────────────────
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "The agent should see KStars planetarium with the sky view."
echo "The transient alert is at: RA 12h 34m 03s, Dec +07° 41' 57\" (NGC 4526)"
echo "Task: Slew telescope, take CCD exposure, capture sky view with ~/capture_sky_view.sh"
