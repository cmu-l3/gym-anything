#!/bin/bash
set -e
echo "=== Setting up aavso_variable_star_campaign task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Images/sscyg
rm -f /home/ga/Documents/aavso_report.txt
rm -f /home/ga/Documents/campaign_brief.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/sscyg/session1
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/sscyg
chown -R ga:ga /home/ga/Documents

# ── 4. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel with standard BVRI + narrowband slots ───
# Slot 1=Luminance, Slot 2=V, Slot 3=B, Slot 4=R, Slot 5=I
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark telescope and slew to WRONG position (agent must find SS Cyg) ──
unpark_telescope
sleep 1
# Point at M31 (Andromeda) - completely wrong target area
slew_to_coordinates 0.712 41.269
wait_for_slew_complete 20
echo "Telescope at M31 (wrong position). Agent must slew to SS Cyg."

# ── 7. Configure CCD upload to a neutral location ──────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the campaign brief document for the agent to discover ────
cat > /home/ga/Documents/campaign_brief.txt << 'EOF'
AAVSO OBSERVING CAMPAIGN BRIEF
===============================
Campaign: SS Cygni Outburst Monitoring
Priority: HIGH - Active Outburst Detected

TARGET INFORMATION
------------------
Star: SS Cygni (SS Cyg)
Type: U Gem type dwarf nova (cataclysmic variable)
Right Ascension: 21h 42m 42.8s
Declination: +43d 35m 10s (J2000)
Constellation: Cygnus
Current V magnitude: ~8.5 (outburst) vs quiescent ~12.0

OBSERVING REQUIREMENTS
----------------------
Filter: V-band (photometric V, second slot in filter wheel)
Exposure time: 45 seconds per frame
Minimum number of frames: 8
CCD upload directory: /home/ga/Images/sscyg/session1/

Capture sky view of the target field with: bash ~/capture_sky_view.sh

COMPARISON STAR
---------------
HD 204188 (comp star C): V = 9.7 mag (same field as SS Cyg)

REPORT SUBMISSION
-----------------
Submit your observations to: /home/ga/Documents/aavso_report.txt

Required format (AAVSO Extended Format):
#TYPE=Extended
#OBSCODE=MYOBS
#SOFTWARE=KStars/INDI Simulator
#DELIM=,
#DATE=JD
#OBSTYPE=CCD
#NAME,DATE,MAG,MERR,FILT,TRANS,MTYPE,CNAME,CMAG,KNAME,KMAG,AMASS,GROUP,CHART,NOTES
SS CYG,2460570.5,8.5,0.05,V,YES,STD,HD204188,9.7,NA,NA,1.1,1,AAVSO,Outburst confirmed

Notes:
- Ensure upload directory is set correctly before imaging
- Images must be LIGHT frames in V-band filter
- Report must identify SS CYG as the target
EOF

chown ga:ga /home/ga/Documents/campaign_brief.txt
echo "Campaign brief written to /home/ga/Documents/campaign_brief.txt"

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
INITIAL_FITS=$(find /home/ga/Images/sscyg 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

# ── 11. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Campaign brief at: ~/Documents/campaign_brief.txt"
echo "Target: SS Cyg (RA 21h 42m 42.8s, Dec +43d 35m 10s)"
echo "Telescope is at M31 - agent must find and slew to SS Cyg"
