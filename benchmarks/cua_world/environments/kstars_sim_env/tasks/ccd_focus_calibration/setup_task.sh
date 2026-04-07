#!/bin/bash
set -e
echo "=== Setting up ccd_focus_calibration task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Images/focus_run
rm -f /home/ga/Documents/focus_procedure.txt
rm -f /home/ga/Documents/focus_report.txt
rm -f /tmp/task_result.json

# ── 3. Create upload directory ─────────────────────────────────────────
mkdir -p /home/ga/Images/focus_run
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/focus_run
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed stale files ──────────────────────────────
# Create fake stale files with a timestamp far in the past (Jan 2024)
touch -t 202401010000 /home/ga/Images/focus_run/old_focus_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/focus_run/old_focus_002.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/focus_run

# ── 5. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope and slew to WRONG position (Polaris) ──────────
unpark_telescope
sleep 1
slew_to_coordinates 2.53 89.26
wait_for_slew_complete 20
echo "Telescope at Polaris (wrong position). Agent must slew to Vega."

# ── 8. Set Focuser to WRONG position ──────────────────────────────────
# Focuser sweet spot is around 30000-40000, 50000 is far out of focus
indi_setprop "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=50000" 2>/dev/null || true
sleep 1

# ── 9. Configure CCD upload to neutral location ────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 10. Create the focus procedure document ───────────────────────────
cat > /home/ga/Documents/focus_procedure.txt << 'EOF'
═══════════════════════════════════════════════════
  CCD FOCUS CALIBRATION PROCEDURE — V-CURVE METHOD
  Observatory Standard Operating Procedure #7
═══════════════════════════════════════════════════

TARGET STAR:    Vega (α Lyrae / HD 172167)
COORDINATES:    RA 18h 36m 56.3s, Dec +38° 47' 01"
                (decimal: RA = 18.6156h, Dec = +38.7836°)

FILTER:         Luminance (Filter Wheel Slot 1)

CCD UPLOAD:     /home/ga/Images/focus_run/
FILE PREFIX:    focus_

FOCUS RANGE:    25000 to 45000 (absolute focuser steps)
STEP SIZE:      2500 steps
POSITIONS:      25000, 27500, 30000, 32500, 35000,
                37500, 40000, 42500, 45000
                (9 positions total)

EXPOSURE:       5 seconds per position

PROCEDURE:
  1. Slew telescope to Vega
  2. Set filter wheel to Luminance (slot 1)
  3. Configure CCD upload directory
  4. For each focuser position in the range:
     a. Set focuser to the target position
     b. Wait 3 seconds for focuser to settle
     c. Take a 5-second exposure (LIGHT frame)
  5. Review images to identify position with sharpest stars
     (smallest FWHM = tightest point sources)
  6. Set focuser to optimal position
  7. Take a final verification exposure at optimal focus
  8. Record results in focus report

OUTPUT REPORT:  /home/ga/Documents/focus_report.txt

Report must include:
  - Date/time of calibration
  - Target star used
  - All focuser positions tested
  - Determined optimal focus position
  - Confirmation that verification image was taken

NOTE: Discard any stale files from previous sessions found
in the upload directory. Only images from this session are valid.
═══════════════════════════════════════════════════
EOF

chown ga:ga /home/ga/Documents/focus_procedure.txt

# ── 11. Ensure KStars is running and maximized ────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 12. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Procedure at: ~/Documents/focus_procedure.txt"