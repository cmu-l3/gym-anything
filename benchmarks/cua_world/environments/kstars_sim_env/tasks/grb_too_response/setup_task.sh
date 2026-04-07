#!/bin/bash
set -e
echo "=== Setting up grb_too_response task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/grb
rm -f /home/ga/Documents/gcn_alert.txt
rm -f /home/ga/Documents/too_protocol.txt
rm -f /home/ga/Documents/gcn_circular.txt
rm -f /tmp/task_result.json

# 3. Create root directories (agent must create confirmation/science subdirs)
mkdir -p /home/ga/Images/grb/221009A
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/grb
chown -R ga:ga /home/ga/Documents

# 4. Start INDI and connect simulators
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 6. Unpark and slew to WRONG position (Polaris region)
unpark_telescope
sleep 1
# Point at Polaris - completely wrong target area
slew_to_coordinates 2.5 89.0
wait_for_slew_complete 20
echo "Telescope at Polaris (wrong position). Agent must slew to GRB."

# 7. Set CCD to neutral default upload location
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create the GCN Alert Notice
cat > /home/ga/Documents/gcn_alert.txt << 'EOF'
///////////////////////////////////////////////////////////////
GCN/SWIFT NOTICE
TYPE: SWIFT BAT GRB POSITION
TRIGGER_NUM: 1126853
GRB_RA:      288.2640d {19h 13m 03.5s} (J2000)
GRB_DEC:     +19.7733d {+19d 46m 24s} (J2000)
GRB_ERROR:   3.0 [arcmin radius, statistical]
GRB_DATE:    24476 TJD;   282 DOY;   2022/10/09
GRB_TIME:    51805.00 SOD {14:23:25.00} UT
TRIGGER_DUR: 300.000 [sec]
TRIGGER_SNR: 1524.00
BKG_DUR:     64.000 [sec]
COMMENTS:
This is an extremely bright burst.  Swift-BAT triggered on
GRB 221009A at 14:23:25 UT.  Fermi-GBM independently triggered.
This is the BRIGHTEST GRB detected in the Swift era.
Immediate follow-up at ALL wavelengths is strongly encouraged.
Automated afterglow detection by UVOT at R~13.0 mag.
///////////////////////////////////////////////////////////////
EOF
chown ga:ga /home/ga/Documents/gcn_alert.txt

# 9. Create the ToO Protocol Document
cat > /home/ga/Documents/too_protocol.txt << 'EOF'
=== OBSERVATORY TARGET-OF-OPPORTUNITY PROTOCOL ===
Document: TOO-OPS-2024-001
Last Updated: 2024-01-15

TRIGGER CRITERIA
  - Any Swift BAT or Fermi GBM GRB trigger with TRIGGER_SNR > 10
  - Current trigger: GRB 221009A (SNR=1524) — QUALIFIES

RESPONSE PROCEDURE

1. SLEW: Immediately slew telescope to GRB coordinates from alert.
   Parse RA and Dec from GCN Notice (J2000 epoch).

2. FILTER: Use Clear/Luminance filter for maximum throughput.
   Filter Wheel Configuration:
     Slot 1: Luminance (Clear)
     Slot 2: Johnson V
     Slot 3: Johnson B
     Slot 4: Johnson R
     Slot 5: H-alpha
     Slot 6: OIII

3. CONFIRMATION PHASE:
   - Upload directory: /home/ga/Images/grb/<GRB_NAME>/confirmation/
   - Take >= 3 images at 10 seconds exposure (LIGHT frames)
   - Purpose: Verify afterglow detection and pointing

4. SCIENCE PHASE:
   - Upload directory: /home/ga/Images/grb/<GRB_NAME>/science/
   - Take >= 10 images at 30 seconds exposure (LIGHT frames)
   - Purpose: Time-series photometry of afterglow decay

5. SKY VIEW: Capture a sky survey view for field identification.
   Save to: /home/ga/Images/grb/<GRB_NAME>/sky_view.png
   Command: bash ~/capture_sky_view.sh /home/ga/Images/grb/<GRB_NAME>/sky_view.png

6. REPORTING: Write GCN Circular to /home/ga/Documents/gcn_circular.txt
   Must include: GRB designation, coordinates, instrument details,
   number of confirmation and science exposures, exposure times.
   Use standard GCN Circular format (TITLE, SUBJECT, DATE, body text).

NOTE: For GRB 221009A, use <GRB_NAME> = "221009A"
Full upload paths:
  /home/ga/Images/grb/221009A/confirmation/
  /home/ga/Images/grb/221009A/science/
===
EOF
chown ga:ga /home/ga/Documents/too_protocol.txt

# 10. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

# 11. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="