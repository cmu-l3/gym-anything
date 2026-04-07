#!/bin/bash
set -e
echo "=== Setting up ccd_instrument_commissioning task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Images/commissioning
rm -f /home/ga/Documents/commissioning_checklist.txt
rm -f /home/ga/Documents/commissioning_report.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/commissioning/filters
mkdir -p /home/ga/Images/commissioning/binning
mkdir -p /home/ga/Images/commissioning/roi
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/commissioning
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed stale/obsolete FITS files ────────────────
# Agent must NOT count these old files as successful binning tests.
# These have a timestamp from January 2024.
touch -t 202401010000 /home/ga/Images/commissioning/binning/old_test_bin1.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/commissioning/binning/old_test_bin2.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/commissioning/binning

# ── 5. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel with generic slots ──────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Slot1" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=Slot2" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=Slot3" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=Slot4" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Slot5" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=Slot6" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope and slew to Zenith (wrong position) ───────────
unpark_telescope
sleep 1
# Point at Zenith (RA 0h, Dec +90d) - far from M45 test target
slew_to_coordinates 0.0 90.0
wait_for_slew_complete 20
echo "Telescope parked at Zenith. Agent must slew to M45."

# ── 8. Reset CCD to default settings ──────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true
# Ensure 1x1 binning
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN=1;VER_BIN=1" 2>/dev/null || true
# Ensure full frame (these values match standard KStars sim max resolution)
indi_setprop "CCD Simulator.CCD_FRAME.X=0;Y=0;WIDTH=3326;HEIGHT=2504" 2>/dev/null || true

# ── 9. Create the commissioning checklist document ────────────────────
cat > /home/ga/Documents/commissioning_checklist.txt << 'EOF'
INSTRUMENT COMMISSIONING CHECKLIST — NEW CCD + WHEEL
=====================================================
Target Field: M45 (Pleiades)
Coordinates:  RA 03h 47m 24s, Dec +24d 07m 00s

INSTRUCTIONS
------------
We need to verify that all hardware control modes for the new camera and
filter wheel are working properly via the Ekos/INDI interface.
Please execute the following 3 tests and save the FITS files to the
specified directories. Use 5-second LIGHT exposures for all tests.

*** TEST 1: FILTER WHEEL ITERATION ***
Directory: /home/ga/Images/commissioning/filters/
Action: Take one 5-second exposure through EACH of the 6 filter slots
        (Slots 1 through 6). Leave binning at 1x1, full frame.

*** TEST 2: CCD BINNING MODES ***
Directory: /home/ga/Images/commissioning/binning/
Action: Using Filter Slot 1, take one 5-second exposure at EACH of the
        following binning levels:
        - 1x1 Binning
        - 2x2 Binning
        - 3x3 Binning
        - 4x4 Binning
        NOTE: Ignore any old/obsolete .fits files already in this folder.

*** TEST 3: ROI / SUBFRAMING ***
Directory: /home/ga/Images/commissioning/roi/
Action: Reset binning to 1x1. Then, configure the CCD to capture a Region
        of Interest (subframe) exactly 1024 x 1024 pixels in size.
        (For example, X=512, Y=512, Width=1024, Height=1024).
        Take one 5-second exposure.

FINAL REPORT
------------
When all 3 tests are complete, create a simple text file at:
/home/ga/Documents/commissioning_report.txt
State that the commissioning checklist has been completed.
EOF

chown ga:ga /home/ga/Documents/commissioning_checklist.txt
echo "Checklist written to /home/ga/Documents/commissioning_checklist.txt"

# ── 10. Ensure KStars is running and maximized ────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="