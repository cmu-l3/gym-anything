#!/bin/bash
set -e
echo "=== Setting up microlensing_caustic_crossing task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Images/microlensing
rm -f /home/ga/Documents/ogle_alert.txt
rm -f /home/ga/Documents/microlensing_response.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/microlensing
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/microlensing
chown -R ga:ga /home/ga/Documents

# ── 4. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel with standard slots ─────────────────────
# Slot 1=Luminance, Slot 2=V, Slot 3=B, Slot 4=R, Slot 5=I
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Park telescope and disable tracking (Agent must undo this) ─────
echo "Parking telescope..."
indi_setprop "Telescope Simulator.TELESCOPE_PARK.PARK=On" 2>/dev/null || true
sleep 2
indi_setprop "Telescope Simulator.ON_COORD_SET.TRACK=Off" 2>/dev/null || true
sleep 1
echo "Telescope is now PARKED. Agent must unpark and enable tracking."

# ── 7. Configure CCD upload to a neutral location ──────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the OGLE alert document for the agent to discover ───────
cat > /home/ga/Documents/ogle_alert.txt << 'EOF'
====================================================================
OGLE EARLY WARNING SYSTEM - CRITICAL ALERT
====================================================================
EVENT: OGLE-2026-BLG-0042
TYPE: Microlensing Caustic Crossing (Planetary Anomaly)
PRIORITY: MAXIMUM (Immediate Override)

OBSERVATIONAL STATUS
--------------------
A planetary companion is currently crossing the primary lensing caustic.
Brightness is spiking rapidly. Time-critical high-cadence photometry
is required IMMEDIATELY to resolve the caustic peak.

TARGET COORDINATES (Galactic Bulge)
-----------------------------------
Right Ascension: 17h 54m 32s
Declination:     -30d 12m 45s (J2000)

OBSERVING PROTOCOL
------------------
1. UNPARK the telescope and ensure TRACKING is ENABLED.
2. Slew to target coordinates.
3. Configure imaging sequence:
   - Filter: R-band (Slot 4)
   - Exposure Time: 15 seconds per frame
   - Sequence Length: Minimum 15 consecutive frames
4. Set Upload Directory EXACTLY to:
   /home/ga/Images/microlensing/OGLE-2026-BLG-0042/
5. Capture a verification sky view of the Bulge field:
   bash ~/capture_sky_view.sh /home/ga/Images/microlensing/OGLE-2026-BLG-0042/sky_field.png

REPORTING
---------
Upon execution, create a brief text log at:
/home/ga/Documents/microlensing_response.txt
Ensure the text contains the event designation "OGLE-2026-BLG-0042" and
notes that the R-band sequence was initiated.

*** DO NOT DELAY. CAUSTIC CROSSING LASTS ONLY HOURS. ***
EOF

chown ga:ga /home/ga/Documents/ogle_alert.txt
echo "Alert written to /home/ga/Documents/ogle_alert.txt"

# ── 9. Ensure KStars is running and maximized ─────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 10. Record initial FITS count for anti-gaming ─────────────────────
INITIAL_FITS=$(find /home/ga/Images/microlensing 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

# ── 11. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="