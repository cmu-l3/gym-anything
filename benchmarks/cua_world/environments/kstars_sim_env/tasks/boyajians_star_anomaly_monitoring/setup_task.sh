#!/bin/bash
set -e
echo "=== Setting up boyajians_star_anomaly_monitoring task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/kic8462852
rm -f /home/ga/Documents/anomaly_alert.txt
rm -f /home/ga/Documents/tabbys_star_report.txt
rm -f /tmp/task_result.json

# ── 3. Create initial base directory and seed stale file ───────────────
# Agent must create the B/, V/, and R/ subdirectories. We just create base.
mkdir -p /home/ga/Images/kic8462852
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/kic8462852
chown -R ga:ga /home/ga/Documents

# ERROR INJECTION: Seed a stale frame from BEFORE task start
touch -t 202401010000 /home/ga/Images/kic8462852/old_b_band_001.fits 2>/dev/null || true
chown ga:ga /home/ga/Images/kic8462852/old_b_band_001.fits

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel for multi-band photometry ───────────────
# Slots: 1=L, 2=V, 3=B, 4=R, 5=I
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark and slew to WRONG position ──────────────────────────────
unpark_telescope
sleep 1
# Point at Sgr A* (Galactic Center) - totally wrong location for Cygnus
slew_to_coordinates 17.761 -29.007
wait_for_slew_complete 20
echo "Telescope parked at Sgr A* (wrong). Agent must slew to KIC 8462852."

# ── 7. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the observing request document ───────────────────────────
cat > /home/ga/Documents/anomaly_alert.txt << 'EOF'
URGENT OBSERVING ALERT — AAVSO / SETI TARGET
=============================================
Target: KIC 8462852 (Boyajian's Star / Tabby's Star)
Priority: MAXIMUM — Anomalous Dimming Event In Progress

TARGET EPHEMERIS
----------------
Right Ascension: 20h 06m 15.4s
Declination:     +44d 27m 24s (J2000)
Constellation: Cygnus

SCIENTIFIC OBJECTIVE
--------------------
To test the "dust vs. megastructure" chromaticity hypothesis, we require
simultaneous multi-band photometry. Solid objects block all wavelengths
equally, while dust scatters blue light more than red.

OBSERVING PROTOCOL
------------------
You must capture sequences in B, V, and R bands and strictly separate the
data into specific subdirectories to feed our automated reduction pipeline.

1. B-band Sequence (Slot 3)
   - Directory: /home/ga/Images/kic8462852/B/
   - Exposure: 60 seconds
   - Count: 10 frames

2. V-band Sequence (Slot 2)
   - Directory: /home/ga/Images/kic8462852/V/
   - Exposure: 60 seconds
   - Count: 10 frames

3. R-band Sequence (Slot 4)
   - Directory: /home/ga/Images/kic8462852/R/
   - Exposure: 60 seconds
   - Count: 10 frames

ADDITIONAL REQUIREMENTS
-----------------------
- Generate a 0.5-degree DSS finding chart using the vibrant palette:
  `bash ~/capture_sky_view.sh ~/Images/kic8462852/finding_chart.png 0.5 --palette vibrant`
- File a brief report to ~/Documents/tabbys_star_report.txt. Include the 
  star's name, its coordinates, and a summary of captured frames.

NOTE: Do not mix frames! Set the upload directory before starting each sequence.
EOF

chown ga:ga /home/ga/Documents/anomaly_alert.txt

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
INITIAL_FITS=$(find /home/ga/Images/kic8462852 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Alert at ~/Documents/anomaly_alert.txt"
echo "Target: KIC 8462852 (RA 20h 06m 15.4s, Dec +44d 27m 24s)"
echo "Telescope at Sgr A* - agent must slew to Cygnus"