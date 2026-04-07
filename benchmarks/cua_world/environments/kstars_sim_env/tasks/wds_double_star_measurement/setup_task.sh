#!/bin/bash
set -e
echo "=== Setting up wds_double_star_measurement task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/doubles
rm -f /home/ga/Documents/wds_request.txt
rm -f /home/ga/Documents/wds_measurements.txt
rm -f /tmp/task_result.json

# ── 3. Create target directories ──────────────────────────────────────
mkdir -p /home/ga/Images/doubles/albireo
mkdir -p /home/ga/Images/doubles/61cyg
mkdir -p /home/ga/Images/doubles/eta_cas
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/doubles
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed stale observation file ───────────────────
# Agent must not include this old file in their counts.
touch -t 202301010000 /home/ga/Images/doubles/albireo/old_obs_2023.fits 2>/dev/null || true
chown ga:ga /home/ga/Images/doubles/albireo/old_obs_2023.fits

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Unpark and slew to WRONG position (Polaris) ────────────────────
unpark_telescope
sleep 1
# Point at Polaris - far from all targets
slew_to_coordinates 2.530 89.264
wait_for_slew_complete 20
echo "Telescope parked near Polaris. Agent must slew to targets."

# ── 7. Reset CCD to a neutral location ────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the observing request document ──────────────────────────
cat > /home/ga/Documents/wds_request.txt << 'EOF'
WASHINGTON DOUBLE STAR (WDS) CATALOG MEASUREMENT REQUEST
=========================================================
Program: Neglected Pairs Campaign
Priority: HIGH

OBSERVING LIST
--------------
We request new astrometric measurements for the following three pairs.

1. Albireo (Beta Cygni)
   WDS Designation: WDS 19307+2758
   Discoverer Code: STF 2486AB
   RA: 19h 30m 43s
   Dec: +27d 57m 35s (J2000)
   Historical specs: PA ~54 deg, Sep ~34.4 arcsec

2. 61 Cygni
   WDS Designation: WDS 21069+3845
   Discoverer Code: STF 2758AB
   RA: 21h 06m 54s
   Dec: +38d 44m 58s (J2000)
   Historical specs: PA ~152 deg, Sep ~31.5 arcsec

3. Eta Cassiopeiae (Achird)
   WDS Designation: WDS 00491+5749
   Discoverer Code: STF 60AB
   RA: 00h 49m 06s
   Dec: +57d 48m 55s (J2000)
   Historical specs: PA ~326 deg, Sep ~13.0 arcsec

OBSERVING PROTOCOL
------------------
For EACH target, execute the following:
  1. Slew the telescope to the target coordinates.
  2. Set the CCD upload directory to the specific target path:
     - Albireo: /home/ga/Images/doubles/albireo/
     - 61 Cygni: /home/ga/Images/doubles/61cyg/
     - Eta Cas: /home/ga/Images/doubles/eta_cas/
  3. Set filter to Luminance (Slot 1 in Filter Wheel).
  4. Capture at least 3 LIGHT frames per target (10 seconds exposure each).

Note: Please ignore any leftover files from previous observers in the
directories. We only need data from tonight's session.

SKY FIELD DOCUMENTATION
-----------------------
Capture at least one sky survey view during your session using:
  bash ~/capture_sky_view.sh

REPORT SUBMISSION
-----------------
Submit your measurements to: /home/ga/Documents/wds_measurements.txt

Required Format:
Provide a plain text file listing each measured pair. Ensure you include
the WDS designation, target name, position angle (theta), separation (rho),
number of observations (n), and filter used.

Example format:
WDS 19307+2758  STF 2486AB  Albireo       theta=054  rho=34.4  n=3  filter=L
WDS 21069+3845  STF 2758AB  61 Cygni      theta=152  rho=31.5  n=3  filter=L
WDS 00491+5749  STF   60AB  Eta Cas       theta=326  rho=13.0  n=3  filter=L
EOF

chown ga:ga /home/ga/Documents/wds_request.txt

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
echo "Observing request placed at ~/Documents/wds_request.txt"