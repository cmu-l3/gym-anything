#!/bin/bash
set -e
echo "=== Setting up ccd_gain_readnoise_characterization task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Calibration/ccd_characterization
rm -f /home/ga/Documents/ccd_test_procedure.txt
rm -f /home/ga/Documents/ccd_characterization_report.txt
rm -f /tmp/task_result.json

# 3. Create root directory
mkdir -p /home/ga/Calibration/ccd_characterization/flats_1s
mkdir -p /home/ga/Calibration/ccd_characterization/flats_5s
mkdir -p /home/ga/Calibration/ccd_characterization/flats_15s
mkdir -p /home/ga/Calibration/ccd_characterization/bias
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Calibration
chown -R ga:ga /home/ga/Documents

# 4. ERROR INJECTION: Seed stale files from BEFORE task start
# These represent a previous aborted calibration attempt
touch -t 202401150800 /home/ga/Calibration/ccd_characterization/flats_1s/old_flat_001.fits
touch -t 202401150801 /home/ga/Calibration/ccd_characterization/flats_1s/old_flat_002.fits
touch -t 202401150802 /home/ga/Calibration/ccd_characterization/bias/old_bias_001.fits
chown -R ga:ga /home/ga/Calibration/ccd_characterization

# 5. Start INDI
ensure_indi_running
sleep 2
connect_all_devices

# 6. Unpark telescope
unpark_telescope
sleep 1

# 7. Set CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create test procedure document
cat > /home/ga/Documents/ccd_test_procedure.txt << 'EOF'
=======================================================
CCD CHARACTERIZATION TEST PROCEDURE
Observatory Instrumentation Lab
=======================================================

PURPOSE:
Measure CCD gain (e-/ADU) and read noise (e-) for the
CCD Simulator using the photon transfer (two-flat) method.

EQUIPMENT:
- CCD Simulator (INDI driver: CCD Simulator)
- Filter Wheel Simulator (not needed — use current filter)

TEST PARAMETERS:
- Flat-field exposure levels: 1 second, 5 seconds, 15 seconds
- Number of flat frames per level: 2 (matched pair)
- Bias frames: minimum 10 frames (0 second exposure)

OUTPUT DIRECTORY:
  /home/ga/Calibration/ccd_characterization/
    flats_1s/     — 2 flat frames at 1s exposure
    flats_5s/     — 2 flat frames at 5s exposure
    flats_15s/    — 2 flat frames at 15s exposure
    bias/         — 10+ bias frames at 0s exposure

NOTE: Stale files from a previous incomplete test may exist
in the flats_1s/ and bias/ directories. Ignore these.

PROCEDURE:
1. Ensure CCD Simulator is connected via INDI
2. For each exposure level (1s, 5s, 15s):
   a. Set CCD frame type to FLAT
   b. Set upload directory to the appropriate subdirectory
   c. Take 2 exposures at the specified duration
3. Set CCD frame type to BIAS
4. Set upload directory to the bias subdirectory
5. Take at least 10 bias frames (0s exposure)
6. Analyze the captured FITS data (e.g., using Python/Astropy):
   - For each flat pair: signal = mean(flat1+flat2)/2
     variance = var(flat1-flat2)/2
   - Gain (e-/ADU) = signal / variance
   - Read noise (ADU) = stddev of combined bias
   - Read noise (e-) = read_noise_ADU * gain
7. Write results to:
   /home/ga/Documents/ccd_characterization_report.txt

REPORT FORMAT:
Include: gain (e-/ADU), read noise (e-), per-level
signal/variance measurements, and date/time of test.
=======================================================
EOF
chown ga:ga /home/ga/Documents/ccd_test_procedure.txt

# 9. Ensure KStars is running
ensure_kstars_running
sleep 3
maximize_kstars
focus_kstars
sleep 1

# 10. Record initial state and screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="