#!/bin/bash
set -e
echo "=== Setting up virgo_sn_patrol task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/patrol
rm -f /home/ga/Documents/patrol_assignment.txt
rm -f /tmp/task_result.json

# ── 3. Create initial directory structure ─────────────────────────────
mkdir -p /home/ga/Images/patrol/virgo/M87
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/patrol
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Stale decoy files ─────────────────────────────
# Create fake stale files in M87 directory with timestamps from Jan 2024
touch -t 202401010000 /home/ga/Images/patrol/virgo/M87/old_patrol_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/patrol/virgo/M87/old_patrol_002.fits 2>/dev/null || true
chown ga:ga /home/ga/Images/patrol/virgo/M87/old_patrol_*.fits 2>/dev/null || true

# ── 5. Ensure INDI server is running ──────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope and slew to Vega (WRONG position) ──────────────
unpark_telescope
sleep 1
# Point at Vega (RA 18.6156h, Dec +38.7837) - far from Virgo
slew_to_coordinates 18.6156 38.7837
wait_for_slew_complete 20
echo "Telescope at Vega. Agent must slew to Virgo Cluster."

# ── 8. Reset CCD to defaults ──────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the patrol assignment document ──────────────────────────
cat > /home/ga/Documents/patrol_assignment.txt << 'EOF'
SUPERNOVA PATROL PROGRAM — VIRGO CLUSTER BLOCK V-3
===================================================
Date: Tonight's Session
Observer: GA Observatory
Program: International Supernova Patrol Network (ISPN)

ASSIGNMENT
----------
Complete imaging patrol of 4 Virgo Cluster galaxies listed below.
All targets must be imaged in Luminance filter (Filter Wheel slot 1).
Take at minimum 4 exposures of 30 seconds each per target (LIGHT frames).

Store images in per-target directories under:
  /home/ga/Images/patrol/virgo/<TARGET_NAME>/

Example: M87 images go to /home/ga/Images/patrol/virgo/M87/

TARGET LIST
-----------
1. M87  (NGC 4486) — Giant Elliptical
   RA:  12h 30m 49.4s  (12.5137 hours)
   Dec: +12° 23' 28"   (+12.3911 degrees)
   Notes: Central Virgo galaxy. Check for jet variability.

2. M84  (NGC 4374) — Lenticular
   RA:  12h 25m 03.7s  (12.4177 hours)
   Dec: +12° 53' 13"   (+12.8869 degrees)
   Notes: Markarian's Chain member. SN 1991bg prototype host.

3. M100 (NGC 4321) — Grand-Design Spiral
   RA:  12h 22m 54.9s  (12.3819 hours)
   Dec: +15° 49' 21"   (+15.8225 degrees)
   Notes: Face-on spiral, excellent for SN detection.

4. M49  (NGC 4472) — Giant Elliptical
   RA:  12h 29m 46.7s  (12.4963 hours)
   Dec: +08° 00' 02"   (+8.0006 degrees)
   Notes: Brightest Virgo Cluster galaxy.

IMAGING PARAMETERS
------------------
- Filter: Luminance (Filter Wheel slot 1)
- Frame Type: LIGHT
- Exposure: 30 seconds
- Minimum frames per target: 4
- CCD Upload Mode: Local

DELIVERABLES
------------
1. Per-target FITS images in the directories specified above
2. Sky view capture (use: bash ~/capture_sky_view.sh) for at least one target
3. Patrol log at: /home/ga/Images/patrol/virgo/patrol_log.txt

PATROL LOG FORMAT
-----------------
The patrol log should include:
- Header with observer name and date
- For each target observed:
  - Target name and NGC number
  - RA and Dec observed
  - Number of frames captured
  - Filter used
  - Any observing notes

Good luck and clear skies!
EOF

chown ga:ga /home/ga/Documents/patrol_assignment.txt

# ── 10. Ensure KStars is running and maximized ────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial FITS count ─────────────────────────────────────
INITIAL_FITS=$(find /home/ga/Images/patrol 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

# ── 12. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Patrol assignment at: ~/Documents/patrol_assignment.txt"
echo "Telescope starts at Vega (far from Virgo Cluster)."