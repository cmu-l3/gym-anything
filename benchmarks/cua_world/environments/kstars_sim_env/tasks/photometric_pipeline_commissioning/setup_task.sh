#!/bin/bash
set -e
echo "=== Setting up photometric_pipeline_commissioning task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean previous artifacts ──────────────────────────────────────
rm -rf /home/ga/Images/focus_test
rm -rf /home/ga/Calibration
rm -rf /home/ga/Science
rm -f  /home/ga/find_best_focus.py
rm -f  /home/ga/reduce_and_calibrate.py
rm -f  /home/ga/Documents/photometric_pipeline.json
rm -f  /home/ga/Documents/commissioning_spec.txt
rm -f  /tmp/task_result.json

# ── 2. Record task start time (AFTER cleanup) ────────────────────────
sleep 1
date +%s > /tmp/task_start_time.txt

# ── 3. Create base directories ──────────────────────────────────────
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# ── 4. Start INDI and connect devices ────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices
sleep 2

# ── 5. Configure filter wheel on both devices ───────────────────────
for DEV in "Filter Simulator" "CCD Simulator"; do
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
    indi_setprop "${DEV}.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
done
sleep 1

# ── 6. Set focuser to defocused position ─────────────────────────────
indi_setprop "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=20000" 2>/dev/null || true
sleep 2

# ── 7. Unpark telescope and slew to WRONG position (anti-gaming) ────
unpark_telescope
sleep 1
slew_to_coordinates 2.5 89.26
wait_for_slew_complete 20

# ── 8. Reset CCD to default upload ──────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Write commissioning specification document ────────────────────
cat > /home/ga/Documents/commissioning_spec.txt << 'SPEC'
================================================================
PHOTOMETRIC SYSTEM COMMISSIONING PROTOCOL
================================================================

You are commissioning the observatory's CCD photometric pipeline.
The CCD is currently DEFOCUSED (focuser position 20000). You must
complete three phases IN ORDER — each phase depends on results
from the previous one.

Equipment:
  Telescope:  Simulator (750mm f/3.75)
  CCD:        Simulator (produces GSC star-field FITS)
  Focuser:    Simulator (range 0–100000, currently at 20000)
  Filters:    V = slot 2, B = slot 3

================================================================
PHASE 1 — FOCUS OPTIMIZATION
================================================================
Target: Vega (Alpha Lyrae)
  RA:   18h 36m 56s
  Dec:  +38 deg 47' 02"

Procedure:
  1. Slew the telescope to Vega.
  2. Using the V-band filter (slot 2), capture one 10-second
     exposure at EACH of these five focuser positions:
       25000, 28000, 31000, 34000, 37000
  3. Save all focus-test frames to:
       ~/Images/focus_test/
  4. Write a Python script at ~/find_best_focus.py that:
     - Loads each FITS file from ~/Images/focus_test/
     - Locates the brightest source (peak pixel)
     - Measures the FWHM (full-width at half-maximum) around
       that source using the second central moment method or
       a Gaussian profile fit
     - Determines which focuser position yields the smallest
       FWHM (sharpest image)
     - Prints: "Best focus: <position> (FWHM: <value> px)"
  5. Run the script and read its output.
  6. SET the focuser to the optimal position before Phase 2.

================================================================
PHASE 2 — DATA ACQUISITION
================================================================

Calibration Frames (no telescope slew needed):
  Bias:
    - Frame type: BIAS (0-second exposure)
    - Count:      10 frames
    - Save to:    ~/Calibration/bias/
  Flats:
    - Frame type: FLAT
    - Filter:     V-band (slot 2)
    - Exposure:   5 seconds
    - Count:      10 frames
    - Save to:    ~/Calibration/flats_V/

Standard Star Field — SA 98 (Landolt):
  RA:   6h 51m 36s
  Dec:  -0 deg 17'
  Procedure:
    - Slew telescope to SA 98
    - Capture 5 x 30s V-band frames  → ~/Science/sa98_V/
    - Capture 5 x 30s B-band frames  → ~/Science/sa98_B/

Science Target — M67 (open cluster):
  RA:   8h 51m 18s
  Dec:  +11 deg 48'
  Procedure:
    - Slew telescope to M67
    - Capture 5 x 30s V-band frames  → ~/Science/m67_V/
    - Capture 5 x 30s B-band frames  → ~/Science/m67_B/

================================================================
PHASE 3 — ANALYSIS PIPELINE
================================================================
Write a Python script at ~/reduce_and_calibrate.py that performs
the complete photometric reduction:

Step 1 — Master Bias:
  Load all 10 bias FITS from ~/Calibration/bias/.
  Compute master_bias = median across all frames (pixel-wise).
  Compute readnoise_adu = standard deviation of master_bias.

Step 2 — Master Flat:
  Load all 10 flat FITS from ~/Calibration/flats_V/.
  Subtract master_bias from each flat frame.
  Compute master_flat = median across bias-subtracted flats.
  Normalize: norm_flat = master_flat / mean(master_flat).

Step 3 — Reduce Science Frames:
  For each science FITS in sa98_V/, sa98_B/, m67_V/, m67_B/:
    reduced = (raw_frame - master_bias) / norm_flat

Step 4 — Aperture Photometry:
  For each reduced frame, measure the brightest star:
    - Find the peak pixel (star center).
    - Star aperture: 15 pixel radius circle.
    - Sky annulus:   inner=25px, outer=35px.
    - flux = sum(star_pixels) - n_star_pixels * median(sky_pixels)
  Compute instrumental magnitude:
    m_inst = -2.5 * log10(flux / exposure_time)

Step 5 — Zero-Point Calibration:
  SA 98 catalog magnitudes (primary standard star):
    V_cat = 10.01
    B_cat = 10.54
  For each filter:
    ZP = m_cat - mean(m_inst for SA 98 frames in that filter)
    ZP_std = std(m_inst for SA 98 frames in that filter)

Step 6 — Calibrated Science Photometry:
  For M67 frames in each filter:
    m_cal = mean(m_inst) + ZP
  Color index:
    m67_BV_color = m67_B_cal - m67_V_cal

Step 7 — Save Results:
  Write ~/Documents/photometric_pipeline.json with these keys:
    best_focus_position    (int — from Phase 1)
    best_fwhm              (float — pixels, from Phase 1)
    readnoise_adu          (float — std of master bias)
    master_flat_mean       (float — mean of master flat)
    zp_V                   (float — V-band zero-point)
    zp_V_std               (float — V-band ZP scatter)
    zp_B                   (float — B-band zero-point)
    zp_B_std               (float — B-band ZP scatter)
    m67_V_cal              (float — M67 calibrated V mag)
    m67_B_cal              (float — M67 calibrated B mag)
    m67_BV_color           (float — B-V color index)
    n_frames_total         (int — total FITS captured: 45)

Validation constraints (sanity checks):
    15.0 < zero-points < 30.0
    |m67_BV_color| < 5.0
    all standard deviations < 1.0
    n_frames_total = 45 (5 focus + 10 bias + 10 flat + 20 science)

Run the script and verify the JSON output is written correctly.
================================================================
SPEC
chown ga:ga /home/ga/Documents/commissioning_spec.txt

# ── 10. Ensure KStars is running and focused ─────────────────────────
ensure_kstars_running
sleep 3
for i in 1 2; do DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 1; done
maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial state ─────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== photometric_pipeline_commissioning setup complete ==="
