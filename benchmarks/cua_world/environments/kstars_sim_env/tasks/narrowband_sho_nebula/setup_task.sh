#!/bin/bash
set -e
echo "=== Setting up narrowband_sho_nebula task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/ngc7000
rm -f /home/ga/Documents/imaging_plan.txt
rm -f /tmp/task_result.json

# ── 3. Create output directories ──────────────────────────────────────
mkdir -p /home/ga/Images/ngc7000/narrowband/Ha
mkdir -p /home/ga/Images/ngc7000/narrowband/OIII
mkdir -p /home/ga/Images/ngc7000/narrowband/SII
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/ngc7000
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel with narrowband slots ───────────────────
# Slots: 1=L, 2=V, 3=B, 4=SII, 5=Ha, 6=OIII
# Agent must discover slot numbers from the filter wheel UI
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=SII" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# ── 6. Unpark and slew to wrong position ──────────────────────────────
unpark_telescope
sleep 1
# Point at M57 (Ring Nebula) - wrong object
slew_to_coordinates 18.893 33.029
wait_for_slew_complete 20
echo "Telescope at M57 (wrong). Agent must find NGC 7000."

# ── 7. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the imaging plan document ───────────────────────────────
cat > /home/ga/Documents/imaging_plan.txt << 'EOF'
ASTROPHOTOGRAPHY IMAGING PLAN — SHO NARROWBAND SEQUENCE
========================================================
Prepared by: Remote Imaging Queue System

TARGET
------
Object: NGC 7000 (North America Nebula)
Type: Emission nebula (HII region)
Right Ascension: 20h 58m 47s
Declination:     +44d 20m 02s (J2000)
Constellation: Cygnus

NARROWBAND FILTER SEQUENCE (SHO = Sulfur-Hydrogen-Oxygen)
----------------------------------------------------------
The Hubble palette maps SHO emission lines to RGB channels:
  Red   = SII  (Sulfur-II,    672nm)
  Green = Ha   (Hydrogen-alpha, 656nm)
  Blue  = OIII (Oxygen-III,   500nm)

Filter wheel configuration for this session:
  Ha   = slot 5  (H-alpha 7nm bandpass)
  OIII = slot 6  (OIII dual-band 7nm)
  SII  = slot 4  (SII 7nm bandpass)

EXPOSURE PLAN
-------------
Per filter:
  - Exposure time: 300 seconds (5 minutes) per frame
  - Number of frames: 5 per filter
  - Total: 15 frames across 3 filters

Upload directories (set before each filter):
  Ha   frames: /home/ga/Images/ngc7000/narrowband/Ha/
  OIII frames: /home/ga/Images/ngc7000/narrowband/OIII/
  SII  frames: /home/ga/Images/ngc7000/narrowband/SII/

PROCEDURE
---------
1. Slew telescope to NGC 7000 coordinates above.
2. Capture Ha frames:
   - Set filter to slot 5 (Ha)
   - Set upload dir to /home/ga/Images/ngc7000/narrowband/Ha/
   - Capture 5 x 300s LIGHT frames
3. Capture OIII frames:
   - Set filter to slot 6 (OIII)
   - Set upload dir to /home/ga/Images/ngc7000/narrowband/OIII/
   - Capture 5 x 300s LIGHT frames
4. Capture SII frames:
   - Set filter to slot 4 (SII)
   - Set upload dir to /home/ga/Images/ngc7000/narrowband/SII/
   - Capture 5 x 300s LIGHT frames
5. Capture sky field survey:
   bash ~/capture_sky_view.sh /home/ga/Images/ngc7000/sky_view.png --palette narrowband
6. Produce SHO composite:
   python3 ~/false_color.py /home/ga/Images/ngc7000/sky_view.png \
       /home/ga/Images/ngc7000/composite_sho.png --palette narrowband

OUTPUT REQUIRED
---------------
Final composite: /home/ga/Images/ngc7000/composite_sho.png

NOTE: The false_color.py script is at ~/false_color.py and the capture
script is at ~/capture_sky_view.sh — both are pre-installed.
EOF

chown ga:ga /home/ga/Documents/imaging_plan.txt

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
INITIAL_FITS=$(find /home/ga/Images/ngc7000 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Imaging plan at ~/Documents/imaging_plan.txt"
echo "Target: NGC 7000 (RA 20h 58m 47s, Dec +44d 20m)"
echo "Filter wheel: Ha=slot5, OIII=slot6, SII=slot4"
echo "Telescope at M57 - agent must find NGC 7000"
