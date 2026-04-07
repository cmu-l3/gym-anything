#!/bin/bash
set -e
echo "=== Setting up ssa_geostationary_belt_stare task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/SSA
rm -f /home/ga/Documents/ssa_tasking_order.txt
rm -f /home/ga/Documents/ssa_report.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ──────────────────────────────────────────────
mkdir -p /home/ga/Images/SSA/geo_stare
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/SSA
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI and connect devices ──────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure Filter Wheel ──────────────────────────────────────────
# Slot 1 is required (Clear/Luminance)
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark, slew to decoy target, and ENSURE TRACKING IS ON ─────────
unpark_telescope
sleep 1
# Point at Ursa Major - away from target
slew_to_coordinates 11.0 55.0
wait_for_slew_complete 20
# Explicitly turn tracking ON so agent has to disable it
indi_setprop 'Telescope Simulator.ON_COORD_SET.TRACK=On' 2>/dev/null || true
echo "Telescope tracking Ursa Major. Tracking is ON."

# ── 7. Reset CCD to defaults ───────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the Tasking Order Document ───────────────────────────────
cat > /home/ga/Documents/ssa_tasking_order.txt << 'EOF'
SPACE SITUATIONAL AWARENESS - TASKING ORDER
===========================================
Priority: HIGH
Target Class: Geostationary Debris / Uncatalogued RSOs

TASK OVERVIEW
-------------
Perform a non-sidereal "stare-mode" survey of the Astra/Eutelsat orbital
cluster insertion point. Geostationary satellites orbit at the exact rate
of the Earth's rotation. To observe them as sharp pinpoints, the telescope
must REMAIN STATIONARY relative to the ground. 

COORDINATES (J2000)
-------------------
Slew to the following celestial coordinates first:
  RA:  21h 15m 00s
  Dec: -05° 15' 00"

EXECUTION REQUIREMENTS
----------------------
1. MOUNT MODE: STARE
   *** CRITICAL: Sidereal tracking MUST BE COMPLETELY DISABLED. ***
   If tracking is left on, GEO satellites will streak and be undetectable.
2. FILTER: Clear / Luminance (Slot 1)
3. CADENCE: 15 consecutive exposures
4. INTEGRATION: 30 seconds per exposure
5. OUTPUT DIR: /home/ga/Images/SSA/geo_stare/

POST-OBSERVATION
----------------
1. Generate a sky view of the final resting field (after coordinate drift)
   using the 'heat' palette:
   bash ~/capture_sky_view.sh ~/Images/SSA/geo_stare/sky_view.png 1.0 --palette heat

2. Submit a brief SSA report to /home/ga/Documents/ssa_report.txt.
   The report must note the starting RA and ending RA to confirm that
   tracking was disabled and coordinate drift occurred.
EOF

chown ga:ga /home/ga/Documents/ssa_tasking_order.txt

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
echo "Tasking order at ~/Documents/ssa_tasking_order.txt"