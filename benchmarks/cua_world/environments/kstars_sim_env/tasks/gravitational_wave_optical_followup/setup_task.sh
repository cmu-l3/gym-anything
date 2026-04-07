#!/bin/bash
set -e
echo "=== Setting up gravitational_wave_optical_followup task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/kilonova_search
rm -f /home/ga/Documents/LVC_Alert_S241120x.txt
rm -f /home/ga/Documents/gcn_response.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ─────────────────────────────────────────────
mkdir -p /home/ga/Images/kilonova_search/ngc4993
mkdir -p /home/ga/Images/kilonova_search/eso508_g019
mkdir -p /home/ga/Images/kilonova_search/ngc4970
mkdir -p /home/ga/Documents

# ── 4. ERROR INJECTION: Seed a stale R-band FITS file ─────────────────
# This prevents the agent from analyzing old files to guess the RMS.
touch -t 202401010000 /home/ga/Images/kilonova_search/ngc4993/old_r_band.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/kilonova_search
chown -R ga:ga /home/ga/Documents

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel for BVRI ────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope and slew to WRONG position ────────────────────
unpark_telescope
sleep 1
# Point at M31 (Andromeda) - RA 0.712h, Dec +41.269°
slew_to_coordinates 0.712 41.269
wait_for_slew_complete 20
echo "Telescope at M31. Agent must interrupt and slew to Hydra-Centaurus region."

# ── 8. Reset CCD to defaults ──────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the LIGO/Virgo Alert Document ───────────────────────────
cat > /home/ga/Documents/LVC_Alert_S241120x.txt << 'EOF'
TITLE:   GCN CIRCULAR
NUMBER:  33921
SUBJECT: LIGO/Virgo S241120x: Identification of Candidate Host Galaxies
DATE:    2024-11-20T04:15:22 GMT

The LIGO Scientific Collaboration and the Virgo Collaboration report the 
detection of a compact binary coalescence candidate (S241120x), highly 
consistent with a binary neutron star (BNS) merger.

The 90% credible region localization has been cross-matched with the 
GLADE galaxy catalog. We have identified three high-probability candidate 
host galaxies for the optical counterpart (kilonova) search.

CANDIDATE 1: NGC 4993
Coordinates: RA 13h 09m 47.7s, Dec -23° 23' 02" (J2000)

CANDIDATE 2: ESO 508-G019
Coordinates: RA 13h 11m 05.8s, Dec -23° 30' 33" (J2000)

CANDIDATE 3: NGC 4970
Coordinates: RA 13h 07m 33.6s, Dec -24° 00' 32" (J2000)

OPTICAL FOLLOW-UP REQUEST:
Observers are requested to image these candidates to search for a rapidly 
fading and reddening transient.

Requirements per target:
- 1 x 15-second exposure in B-band
- 1 x 15-second exposure in R-band
- Calculate the background sky noise (RMS pixel standard deviation) of the R-band images.
- Submit a response circular with the R-band RMS depth.
EOF

chown ga:ga /home/ga/Documents/LVC_Alert_S241120x.txt

# ── 10. Ensure KStars is running and maximized ─────────────────────────
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