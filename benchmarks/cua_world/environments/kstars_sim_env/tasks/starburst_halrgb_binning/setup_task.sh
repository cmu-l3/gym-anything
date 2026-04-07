#!/bin/bash
set -e
echo "=== Setting up starburst_halrgb_binning task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/m82_superwind
rm -f /home/ga/Documents/m82_imaging_plan.txt
rm -f /home/ga/Documents/m82_observation_log.txt
rm -f /tmp/task_result.json

# ── 3. Create output directories and inject stale files ────────────────
mkdir -p /home/ga/Images/m82_superwind/L
mkdir -p /home/ga/Images/m82_superwind/R
mkdir -p /home/ga/Images/m82_superwind/G
mkdir -p /home/ga/Images/m82_superwind/B
mkdir -p /home/ga/Images/m82_superwind/Ha
mkdir -p /home/ga/Documents

# ERROR INJECTION: Create fake stale Ha frames from a previous failed run
# These must NOT be counted by the verifier (mtime will be well before task start)
touch -t 202401010000 /home/ga/Images/m82_superwind/Ha/stale_ha_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/m82_superwind/Ha/stale_ha_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/m82_superwind/Ha/stale_ha_003.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/m82_superwind
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=G" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
sleep 1

# ── 6. Unpark and slew to distractor position ─────────────────────────
unpark_telescope
sleep 1
# Point at M81 (Bode's Galaxy) - close, but the WRONG galaxy.
# RA 9h 55m 33s (9.9258h), Dec +69d 03m 55s (69.0653d)
slew_to_coordinates 9.9258 69.0653
wait_for_slew_complete 20
echo "Telescope tracking distractor M81. Agent must slew 37 arcminutes north to M82."

# ── 7. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN;VER_BIN=1;1" 2>/dev/null || true

# ── 8. Create the imaging plan document ───────────────────────────────
cat > /home/ga/Documents/m82_imaging_plan.txt << 'EOF'
============================================================
 M82 STARBURST GALAXY SUPERWIND — IMAGING PLAN
 PI: Dr. S. Veilleux, Galactic Outflows Group
 Date Prepared: Current Observing Session
============================================================

TARGET:
  Name:        M82 (NGC 3034, Cigar Galaxy)
  Type:        Starburst Galaxy
  RA (J2000):  09h 55m 52.2s
  Dec (J2000): +69° 40' 47"
  
  WARNING: Telescope is currently tracking M81 (Bode's Galaxy) 
  which is ~37 arcminutes away. You MUST slew explicitly to 
  M82's coordinates to center the bipolar outflow. Do not assume 
  the current field of view is acceptable.

SCIENTIFIC GOAL:
  Map the ionized hydrogen (H-alpha) superwind erupting from 
  the galactic disk. To maximize SNR for faint emission while 
  retaining high-resolution continuum details, we use a hybrid 
  binning strategy (L=1x1, Color/Narrowband=2x2).

INSTRUMENT CONFIGURATION & SEQUENCE:
  Note: Set binning via Ekos Camera module before capturing.

  1. LUMINANCE (High Resolution Disk Structure)
     - Filter Slot: 1 (L)
     - Binning: 1x1
     - Exposure: 10 seconds
     - Minimum Frames: 5
     - Save Path: /home/ga/Images/m82_superwind/L/

  2. COLOR (Stellar Continuum)
     - Filter Slots: 4 (R), 2 (G), 3 (B)
     - Binning: 2x2
     - Exposure: 10 seconds
     - Minimum Frames: 5 per filter
     - Save Paths: /home/ga/Images/m82_superwind/R/ (and G/ and B/)

  3. NARROWBAND (Ionized Gas Outflow)
     - Filter Slot: 5 (Ha)
     - Binning: 2x2
     - Exposure: 60 seconds
     - Minimum Frames: 5
     - Save Path: /home/ga/Images/m82_superwind/Ha/
     - NOTE: Ignore any stale files in this directory!

DELIVERABLES:
  - All requested FITS frames correctly routed to subdirectories.
  - A sky view capture saved to /home/ga/Images/m82_superwind/m82_sky_view.png
    (Run: bash ~/capture_sky_view.sh /home/ga/Images/m82_superwind/m82_sky_view.png)
  - A brief text file confirming completion at /home/ga/Documents/m82_observation_log.txt
EOF

chown ga:ga /home/ga/Documents/m82_imaging_plan.txt

# ── 9. Ensure KStars is running ────────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 10. Record initial state ───────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Imaging plan at ~/Documents/m82_imaging_plan.txt"
echo "Target: M82 (RA 9h 55m 52.2s, Dec +69d 40m 47s)"
echo "Telescope initialized at M81 - agent must discover and slew to M82."