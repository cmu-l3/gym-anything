#!/bin/bash
set -e
echo "=== Setting up xray_optical_counterpart_search task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/xray_followup
rm -f /home/ga/Documents/xray_targets.txt
rm -f /home/ga/Documents/optical_followup_report.txt
rm -f /tmp/task_result.json

# ── 3. Create root directory ──────────────────────────────────────────
mkdir -p /home/ga/Images/xray_followup
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/xray_followup
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel for BVRI ────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark telescope and slew to a neutral position ────────────────
unpark_telescope
sleep 1
# Point at celestial equator, away from targets
slew_to_coordinates 0.0 0.0
wait_for_slew_complete 20
echo "Telescope at RA 0h, Dec 0° (neutral). Agent must slew to targets."

# ── 7. Reset CCD to defaults ──────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the alert specification document ────────────────────────
cat > /home/ga/Documents/xray_targets.txt << 'EOF'
X-RAY TRANSIENT OPTICAL FOLLOW-UP ALERT
========================================
Issued by: High-Energy Alert Network
Priority: TIME-CRITICAL

The following three X-ray binaries have entered an active state.
Please obtain deep optical baseline images in B and V bands.

TARGET 1: Cygnus X-1 (cygx1)
RA:  19h 58m 21.6s
Dec: +35d 12m 05s

TARGET 2: Scorpius X-1 (scox1)
RA:  16h 19m 55.0s
Dec: -15d 38m 25s

TARGET 3: V404 Cygni (v404cyg)
RA:  20h 24m 03.8s
Dec: +33d 52m 02s

OBSERVATION PROTOCOL
--------------------
For EACH target:
1. Slew to the target coordinates.
2. Set the CCD upload directory to: /home/ga/Images/xray_followup/<target_dir>/
   (e.g., /home/ga/Images/xray_followup/cygx1/)
3. Filter B (slot 3): Capture 5 x 20-second LIGHT frames.
4. Filter V (slot 2): Capture 5 x 20-second LIGHT frames.
5. Sky capture: Generate an optical field reference image using the "cool" palette:
   bash ~/capture_sky_view.sh /home/ga/Images/xray_followup/<target_dir>/optical_field.png 0.25 --palette cool

REPORTING
---------
When all 3 targets are complete, create a summary report at:
/home/ga/Documents/optical_followup_report.txt
List the targets observed and confirm the data has been collected.
EOF

chown ga:ga /home/ga/Documents/xray_targets.txt
echo "Target list written to /home/ga/Documents/xray_targets.txt"

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

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Spec at ~/Documents/xray_targets.txt"