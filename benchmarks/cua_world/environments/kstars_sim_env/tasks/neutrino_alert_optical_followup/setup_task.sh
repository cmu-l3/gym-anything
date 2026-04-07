#!/bin/bash
set -e
echo "=== Setting up neutrino_alert_optical_followup task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/neutrino_followup
rm -f /home/ga/Documents/gcn_alert_IceCube170922A.txt
rm -f /home/ga/Documents/gcn_circular_draft.txt
rm -f /tmp/task_result.json

# ── 3. Create directories & Error Injection (stale data) ──────────────
mkdir -p /home/ga/Images/neutrino_followup/TXS_0506+056
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images
chown -R ga:ga /home/ga/Documents

# ERROR INJECTION: Create fake stale data for one candidate from a previous run
# The agent must not rely on these or count them. They pre-date the task_start_time.
touch -t 202401010000 /home/ga/Images/neutrino_followup/TXS_0506+056/old_v1.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/neutrino_followup/TXS_0506+056/old_v2.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/neutrino_followup/TXS_0506+056/old_r1.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/neutrino_followup/TXS_0506+056/dss_reference.png 2>/dev/null || true
chown -R ga:ga /home/ga/Images/neutrino_followup/TXS_0506+056

# ── 4. Start INDI & connect ────────────────────────────────────────────
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

# ── 6. Unpark and slew to neutral position ────────────────────────────
unpark_telescope
sleep 1
# Point to South Galactic Pole (RA 0h 51m = 0.85h, Dec -27.15 deg) to ensure a large slew to Orion/Taurus area
slew_to_coordinates 0.85 -27.15
wait_for_slew_complete 20
echo "Telescope at South Galactic Pole. Agent must find the targets."

# ── 7. Configure CCD upload ───────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the GCN alert document ──────────────────────────────────
cat > /home/ga/Documents/gcn_alert_IceCube170922A.txt << 'EOF'
TITLE:   GCN CIRCULAR
NUMBER:  21916
SUBJECT: IceCube-170922A - IceCube observation of a high-energy neutrino candidate track-like event
DATE:    17/09/22 20:54:30 GMT
FROM:    IceCube Collaboration

The IceCube Neutrino Observatory has detected a high-energy neutrino candidate track-like event.

We strongly encourage optical follow-up of the error region to identify a potential flaring counterpart. Three known blazars (gamma-ray active galactic nuclei) are located within the 90% containment area and are considered primary candidates.

CANDIDATE 1: TXS 0506+056
-------------------------
Type: BL Lacertae object
RA:  05h 09m 25.96s
Dec: +05d 41m 35.3s (J2000)

CANDIDATE 2: PKS 0502+049
-------------------------
Type: Flat Spectrum Radio Quasar
RA:  05h 05m 23.0s
Dec: +04d 59m 43.0s (J2000)

CANDIDATE 3: GB6 J0512+0529
-------------------------
Type: Blazar
RA:  05h 12m 45.0s
Dec: +05d 29m 00.0s (J2000)

OPTICAL FOLLOW-UP PROTOCOL
--------------------------
ToO Operations: You must observe ALL THREE candidates.
For each candidate:
1. Slew to target.
2. Filter: V-band (slot 2). Take 3 x 60-second exposures.
3. Filter: R-band (slot 4). Take 3 x 60-second exposures.
4. Upload Directory: Store frames in ~/Images/neutrino_followup/<candidate_name>/
   (e.g., ~/Images/neutrino_followup/TXS_0506+056/)
5. Capture a 0.5-degree reference image named 'dss_reference.png' in the target's directory.
   Use the 'cool' false-color palette.
   Command format: bash ~/capture_sky_view.sh [output_path] 0.5 --palette cool

After completing all three candidates, draft a confirmation report to:
~/Documents/gcn_circular_draft.txt

The report must confirm observation of all three candidates by naming them.
EOF

chown ga:ga /home/ga/Documents/gcn_alert_IceCube170922A.txt

# ── 9. Ensure KStars is running ───────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 10. Record initial state ──────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "GCN Alert generated at ~/Documents/gcn_alert_IceCube170922A.txt"