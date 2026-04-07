#!/bin/bash
set -e
echo "=== Setting up xray_binary_optical_counterparts task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/xray_followup
rm -f /home/ga/Documents/xray_target_list.txt
rm -f /home/ga/Documents/xray_followup_report.txt
rm -f /tmp/task_result.json

# ── 3. Create directories & error injection ────────────────────────────
mkdir -p /home/ga/Images/xray_followup/CygnusX1
mkdir -p /home/ga/Documents

# Inject stale frames from BEFORE task start
touch -t 202401010000 /home/ga/Images/xray_followup/CygnusX1/stale_frame_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/xray_followup/CygnusX1/stale_frame_002.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/xray_followup
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark and slew to wrong position (Polaris) ────────────────────
unpark_telescope
sleep 1
slew_to_coordinates 2.5 89.0
wait_for_slew_complete 20
echo "Telescope parked near Celestial Pole. Agent must slew to targets."

# ── 7. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the Target List Document ────────────────────────────────
cat > /home/ga/Documents/xray_target_list.txt << 'EOF'
HIGH-MASS X-RAY BINARY / MICROQUASAR OPTICAL FOLLOW-UP LIST
===========================================================
Priority: URGENT (MAXI Alert Trigger)

Target 1: Cygnus X-1
RA: 19h 58m 21.6s
Dec: +35d 12m 05.7s

Target 2: V404 Cygni
RA: 20h 24m 03.8s
Dec: +33d 52m 02.2s

Target 3: SS 433
RA: 19h 11m 49.5s
Dec: +04d 58m 57.8s

REQUIREMENTS PER TARGET:
- Directory name: CygnusX1, V404Cygni, SS433
- Filter: V-band (Slot 2)
- Exposure: 3 frames x 15 seconds
- Finding chart: 0.5 deg FOV, cool palette
EOF

chown ga:ga /home/ga/Documents/xray_target_list.txt

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