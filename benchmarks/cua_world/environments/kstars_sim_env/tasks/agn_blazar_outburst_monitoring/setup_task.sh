#!/bin/bash
set -e
echo "=== Setting up agn_blazar_outburst_monitoring task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/ToO
rm -f /home/ga/Documents/ATel_alert_Mrk421.txt
rm -f /home/ga/Documents/ATel_response.txt
rm -f /tmp/task_result.json

# ── 3. Create target directory ────────────────────────────────────────
mkdir -p /home/ga/Images/ToO/Mrk421
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/ToO
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI and connect devices ─────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel ─────────────────────────────────────────
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
# Point at Arcturus (RA 14h 15m 39s, Dec +19d 10m 56s) - completely wrong target
slew_to_coordinates 14.261 19.182
wait_for_slew_complete 20
echo "Telescope at Arcturus (wrong position). Agent must slew to Mrk 421."

# ── 7. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the ToO alert document ──────────────────────────────────
cat > /home/ga/Documents/ATel_alert_Mrk421.txt << 'EOF'
TARGET OF OPPORTUNITY (ToO) ALERT
==================================
Priority: MAXIMUM (Override current queue)
Source: Astronomer's Telegram (ATel) Network

EVENT DESCRIPTION
-----------------
Space-based observatories have detected a massive X-ray and Gamma-ray flare
originating from the blazar Markarian 421 (Mrk 421). Ground-based optical
follow-up is requested immediately to construct a multi-wavelength Spectral
Energy Distribution (SED).

TARGET PARAMETERS
-----------------
Object: Markarian 421 (Mrk 421)
Type: Blazar / BL Lac object
Right Ascension: 11h 04m 27s
Declination: +38d 12m 32s (J2000)
Constellation: Ursa Major

OBSERVATION REQUIREMENTS
------------------------
1. CCD Upload Directory: /home/ga/Images/ToO/Mrk421/
2. Execute the following sequence:
   - Filter B (Slot 3): 5 exposures, 60 seconds each
   - Filter V (Slot 2): 5 exposures, 60 seconds each
   - Filter R (Slot 4): 5 exposures, 60 seconds each
   (Frame type must be LIGHT for all)

CONTEXT IMAGE REQUIREMENT
-------------------------
We need a false-color sky survey context image mimicking a high-energy view.
Run the following script command exactly as written:
bash ~/capture_sky_view.sh /home/ga/Images/ToO/Mrk421/xray_context.png 1.0 --palette cool

RESPONSE REQUIREMENT
--------------------
Draft a brief confirmation telegram at: /home/ga/Documents/ATel_response.txt
The draft must explicitly mention the target "Mrk 421" and confirm that
"B", "V", and "R" band data were acquired.
EOF

chown ga:ga /home/ga/Documents/ATel_alert_Mrk421.txt

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
echo "Alert file: ~/Documents/ATel_alert_Mrk421.txt"