#!/bin/bash
set -e
echo "=== Setting up telescope_collimation_star_test task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Maintenance/collimation_test
rm -f /home/ga/Documents/maintenance_ticket_104.txt
rm -f /tmp/task_result.json

# ── 3. Create necessary directories ────────────────────────────────────
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Maintenance
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/Maintenance

# ── 4. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel with standard slots ─────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Error Injection / Initial State (Agent must fix these) ─────────
# Park telescope at the pole (so it's not pointing at Capella)
unpark_telescope
sleep 1
slew_to_coordinates 0.0 90.0
wait_for_slew_complete 20
park_telescope
sleep 1

# Set the Focuser to a random broken absolute position
indi_setprop "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=18342" 2>/dev/null || true

# Set the CCD to default upload dir (Agent must change it)
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 7. Create the maintenance ticket document ─────────────────────────
cat > /home/ga/Documents/maintenance_ticket_104.txt << 'EOF'
OPTICAL MAINTENANCE TICKET #104
================================
Task: Primary Mirror Collimation Star Test
Target: Capella (RA 05h 16m 41s, Dec +45d 59m 52s)
Filter: V-Band (Slot 2) to minimize chromatic dispersion
Output Dir: /home/ga/Maintenance/collimation_test/

PROCEDURE:
1. Unpark and Slew to Capella.
2. Set filter to V-band (slot 2).
3. Create the Output Dir and set the CCD upload directory to it.
4. Capture Nominal Focus:
   - Move focuser to absolute position: 50000
   - Set CCD upload prefix to: focus_50000_
   - Take 5s LIGHT exposure
5. Capture Intra-focal:
   - Move focuser to absolute position: 40000
   - Set CCD upload prefix to: focus_40000_
   - Take 5s LIGHT exposure
6. Capture Extra-focal:
   - Move focuser to absolute position: 60000
   - Set CCD upload prefix to: focus_60000_
   - Take 5s LIGHT exposure
7. Capture Sky Context:
   - Run: bash ~/capture_sky_view.sh /home/ga/Maintenance/collimation_test/field_context.png 1.0 --palette enhanced
8. Write a brief completion report to report.txt in the Output Dir containing the target name "Capella".

NOTES:
- Use INDI properties to set the upload directory and prefix.
- All files must be saved correctly into the output dir.
EOF

chown ga:ga /home/ga/Documents/maintenance_ticket_104.txt

# ── 8. Ensure KStars is running and maximized ─────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 9. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Maintenance ticket generated at ~/Documents/maintenance_ticket_104.txt"
echo "Telescope is currently PARKED at the pole. Focuser is out of alignment."