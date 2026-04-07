#!/bin/bash
set -e
echo "=== Setting up calibration_library_production task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Calibration
rm -f /home/ga/Documents/cal_requirements.txt
rm -f /tmp/task_result.json

# ── 3. Create calibration directory structure ──────────────────────────
# Agent must create the LEAF directories — we pre-create the root only
mkdir -p /home/ga/Calibration
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Calibration
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed 3 stale bias frames from BEFORE task start ──
# These should NOT count toward the required 10 (they predate the session)
mkdir -p /home/ga/Calibration/bias
# Create fake stale files by touching them BEFORE recording start time
# (We do this before overwriting task_start_time.txt below)
touch -t 202401010000 /home/ga/Calibration/bias/old_bias_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Calibration/bias/old_bias_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Calibration/bias/old_bias_003.fits 2>/dev/null || true
# These files are zero-length stubs - not valid calibration frames
# Agent must NOT count these toward the required 10 bias frames
chown -R ga:ga /home/ga/Calibration/bias

# NOTE: task_start_time.txt was already written at step 1; the stale
# files above have timestamps from 2024 so they predate the task.

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel for BVRI ────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope ────────────────────────────────────────────────
unpark_telescope
sleep 1

# ── 8. Set CCD to defaults ────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the calibration requirements document ───────────────────
cat > /home/ga/Documents/cal_requirements.txt << 'EOF'
CCD CALIBRATION LIBRARY REQUIREMENTS
=====================================
Approved by: Observatory Director
Session: Current Observing Night

OVERVIEW
--------
A complete calibration library must be built before science observations
begin. All calibration frames must be captured during this session.
NOTE: There are 3 stale bias files in ~/Calibration/bias/ from a
previous session — these do NOT count toward the required totals.

REQUIRED CALIBRATION FRAMES
----------------------------

1. BIAS FRAMES
   Type: BIAS (0-second exposure)
   Count: 10 frames (NEW frames, not including the 3 stale files)
   Directory: /home/ga/Calibration/bias/
   INDI setting: CCD Simulator.CCD_FRAME_TYPE.FRAME_BIAS=On
   Exposure: 0 seconds (CCD_EXPOSURE_VALUE=0)

2. DARK FRAMES — SHORT SERIES
   Type: DARK (300-second exposure)
   Count: 10 frames
   Directory: /home/ga/Calibration/darks/300s/
   INDI setting: CCD Simulator.CCD_FRAME_TYPE.FRAME_DARK=On
   Exposure: 300 seconds (CCD_EXPOSURE_VALUE=300)

3. DARK FRAMES — LONG SERIES
   Type: DARK (600-second exposure)
   Count: 10 frames
   Directory: /home/ga/Calibration/darks/600s/
   INDI setting: CCD Simulator.CCD_FRAME_TYPE.FRAME_DARK=On
   Exposure: 600 seconds (CCD_EXPOSURE_VALUE=600)

4. FLAT FIELDS — V BAND
   Type: FLAT (3-second exposure)
   Count: 5 frames
   Filter: V-band (slot 2 in filter wheel)
   Directory: /home/ga/Calibration/flats/V/
   INDI setting: CCD Simulator.CCD_FRAME_TYPE.FRAME_FLAT=On

5. FLAT FIELDS — R BAND
   Type: FLAT (3-second exposure)
   Count: 5 frames
   Filter: R-band (slot 4 in filter wheel)
   Directory: /home/ga/Calibration/flats/R/
   INDI setting: CCD Simulator.CCD_FRAME_TYPE.FRAME_FLAT=On

6. FLAT FIELDS — B BAND
   Type: FLAT (3-second exposure)
   Count: 5 frames
   Filter: B-band (slot 3 in filter wheel)
   Directory: /home/ga/Calibration/flats/B/
   INDI setting: CCD Simulator.CCD_FRAME_TYPE.FRAME_FLAT=On

DIRECTORY STRUCTURE REQUIRED
-----------------------------
/home/ga/Calibration/
    bias/
    darks/
        300s/
        600s/
    flats/
        V/
        R/
        B/

SUMMARY REPORT
--------------
After completing all calibration frames, create a summary file at:
/home/ga/Calibration/calibration_summary.txt

Required content:
  # CCD Calibration Library Summary
  # Generated: <date>
  bias_frames: 10
  dark_300s_frames: 10
  dark_600s_frames: 10
  flat_V_frames: 5
  flat_R_frames: 5
  flat_B_frames: 5
  total_frames: 45
  status: COMPLETE

IMPORTANT NOTES
---------------
- Set the upload directory BEFORE each series of frames
- Change the frame type (BIAS/DARK/FLAT) for each series
- Change the filter (for flats) before each flat series
- The 3 stale bias files (old_bias_001.fits, old_bias_002.fits, old_bias_003.fits)
  should remain in the bias/ directory but are NOT part of this session's library
EOF

chown ga:ga /home/ga/Documents/cal_requirements.txt

# ── 10. Ensure KStars is running ───────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial state ───────────────────────────────────────────
INITIAL_BIAS=$(find /home/ga/Calibration/bias 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_BIAS" > /tmp/initial_bias_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Requirements at ~/Documents/cal_requirements.txt"
echo "3 stale bias files pre-seeded (should NOT count)"
echo "Agent must build complete calibration library from scratch"
