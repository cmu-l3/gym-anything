#!/bin/bash
set -e
echo "=== Setting up neo_astrometry_verification task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/asteroids
rm -f /home/ga/Documents/neo_obs_request.txt
rm -f /home/ga/Documents/mpc_report.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ──────────────────────────────────────────────
mkdir -p /home/ga/Images/asteroids/2020QG
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/asteroids
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Unpark and slew to wrong position ──────────────────────────────
unpark_telescope
sleep 1
# Point at M13 (Hercules Globular Cluster) - wrong direction
slew_to_coordinates 16.695 36.461
wait_for_slew_complete 20
echo "Telescope at M13 (wrong). Agent must find 2020 QG."

# ── 6. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 7. Create the observing request document ───────────────────────────
cat > /home/ga/Documents/neo_obs_request.txt << 'EOF'
MINOR PLANET CENTER - INDEPENDENT ASTROMETRY REQUEST
=====================================================
Request ID: MPC-NEO-2024-0847
Priority: URGENT

TARGET OBJECT
-------------
Designation: 2020 QG
Object class: Apollo-type near-Earth asteroid
Discovery: 2020-08-16 (Zwicky Transient Facility)
Note: This asteroid had the closest recorded flyby of Earth
      in history (without impact) on 2020-08-16 at ~2,950 km.

PREDICTED POSITION (for this observation)
-----------------------------------------
Right Ascension: 16h 52m 58s
Declination:    -21d 55m 00s (J2000)
Magnitude:       ~17.5 (faint — use CCD)
Motion:          ~2 arcsec/min

OBSERVING REQUIREMENTS
----------------------
CCD upload directory: /home/ga/Images/asteroids/2020QG/
Frame type: LIGHT
Filter: Luminance (no filter / slot 1)
Exposure time: 30 seconds per frame
Minimum number of frames: 6

Note: Take all frames at the same sky position (asteroid moves slowly
enough that it will remain in the CCD field for a 6-frame series).

Capture sky view: bash ~/capture_sky_view.sh /home/ga/Images/asteroids/2020QG/sky_field.png

ASTROMETRY REPORT
-----------------
After observations, submit an MPC-format astrometry report to:
/home/ga/Documents/mpc_report.txt

Required content:
  Line 1: COD 945   (MPC observatory code for Pittsburgh, PA)
  Line 2: OBS Your Name
  Line 3: MEA Your Name
  Line 4: TEL 0.3-m f/10 Schmidt-Cassegrain + CCD
  Line 5: ACK MPC Urgent Request MPC-NEO-2024-0847
  Line 6 onwards: observation data block

Observation data must include:
  - Object designation: "2020 QG"
  - Observed RA and Dec (as close as possible to predicted position)
  - Date of observation (current date)
  - Observer information

Example format line:
     2020 QG          C2024 08 14.07500 16 52 58.0 -21 55 00  17.5 N      945

NOTES
-----
- Frames must be new (captured during this session)
- Report is required for MPC database update
- Coordinate accuracy within 2 degrees of predicted position is acceptable
EOF

chown ga:ga /home/ga/Documents/neo_obs_request.txt

# ── 8. Ensure KStars is running ────────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 9. Record initial state ────────────────────────────────────────────
INITIAL_FITS=$(find /home/ga/Images/asteroids 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Request at ~/Documents/neo_obs_request.txt"
echo "Target: 2020 QG (RA 16h 52m 58s, Dec -21d 55m)"
echo "Telescope at M13 - agent must slew to asteroid field"
