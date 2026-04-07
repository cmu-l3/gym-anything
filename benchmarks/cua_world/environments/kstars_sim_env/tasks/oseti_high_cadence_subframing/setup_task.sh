#!/bin/bash
set -e
echo "=== Setting up oseti_high_cadence_subframing task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Clean up & Create directories ───────────────────────────────────
rm -rf /home/ga/Images/oseti
rm -f /home/ga/Documents/seti_alert_protocol.txt
rm -f /home/ga/Documents/oseti_observation_log.txt
rm -f /tmp/task_result.json

mkdir -p /home/ga/Images/oseti/kic8462852
mkdir -p /home/ga/Documents

# ── 2. ERROR INJECTION: Seed stale FITS files ──────────────────────────
# These have timestamps from 2024 to test if the agent/verifier correctly ignores old data
touch -t 202401010000 /home/ga/Images/oseti/kic8462852/stale_frame_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/oseti/kic8462852/stale_frame_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/oseti/kic8462852/stale_frame_003.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/oseti/kic8462852/stale_frame_004.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/oseti/kic8462852/stale_frame_005.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/oseti

# ── 3. Record task start time (must happen AFTER touching stale files) ─
date +%s > /tmp/task_start_time.txt

# ── 4. Start INDI and connect devices ──────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel ──────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark and slew away to a wrong target (Altair) ─────────────────
unpark_telescope
sleep 1
slew_to_coordinates 19.846 8.868
wait_for_slew_complete 20
echo "Telescope at Altair (wrong). Agent must parse protocol and slew to target."

# ── 7. Reset CCD to defaults (Full Frame, standard directory) ──────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true
# Reset ROI to full frame (setting width/height beyond max forces a full frame reset in simulator)
indi_setprop "CCD Simulator.CCD_FRAME.X=0;Y=0;WIDTH=4000;HEIGHT=4000" 2>/dev/null || true

# ── 8. Create alert protocol ───────────────────────────────────────────
cat > /home/ga/Documents/seti_alert_protocol.txt << 'EOF'
OPTICAL SETI ALERT PROTOCOL
===========================
PRIORITY: CRITICAL - IMMEDIATE FOLLOW-UP REQUIRED
Source: Automated Sky Monitor Network
Event: Suspected rapid optical pulses

TARGET INFORMATION
------------------
Star: KIC 8462852 (Boyajian's Star)
Right Ascension: 20h 06m 15.45s
Declination: +44d 27m 24.6s (J2000)
Constellation: Cygnus

OBSERVING REQUIREMENTS
----------------------
We need high-cadence, short-exposure imaging to resolve rapid pulses.
A full-frame readout takes too long. You MUST configure a subframe.

1. CCD CONFIGURATION:
   - ROI / Subframe Width: Exactly 512 pixels
   - ROI / Subframe Height: Exactly 512 pixels
   - Exposure Time: 1.0 second exactly
   - Filter: Slot 1 (Luminance/Clear)
   - Frame Type: LIGHT

2. UPLOAD DIRECTORY:
   - Must be set to: /home/ga/Images/oseti/kic8462852/
   (Note: Ignore any stale files in this directory from previous runs)

3. CAPTURE SEQUENCE:
   - Capture at least 20 continuous exposures of the target field.

4. REFERENCE SKY VIEW:
   - Capture a visual reference using the system script:
     bash ~/capture_sky_view.sh ~/Images/oseti/kic8462852/reference_sky.png --palette cool

5. LOGGING:
   - Create a brief report at: /home/ga/Documents/oseti_observation_log.txt
   - State the target name and confirm that 20+ subframed files were captured.
EOF
chown ga:ga /home/ga/Documents/seti_alert_protocol.txt

# ── 9. Start KStars ────────────────────────────────────────────────────
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
echo "Protocol at ~/Documents/seti_alert_protocol.txt"