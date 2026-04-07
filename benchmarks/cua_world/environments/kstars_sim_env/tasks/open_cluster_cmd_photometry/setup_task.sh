#!/bin/bash
set -e
echo "=== Setting up open_cluster_cmd_photometry task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/m44_cmd
rm -f /home/ga/Documents/m44_observing_plan.txt
rm -f /home/ga/Documents/m44_cmd_report.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory base ───────────────────────────────────
# Agent must create the B/ and V/ leaf directories
mkdir -p /home/ga/Images/m44_cmd
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/m44_cmd
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed stale files ──────────────────────────────
# Create fake stale files from a previous run before the task start time
touch -t 202401010000 /home/ga/Images/m44_cmd/old_attempt_b_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/m44_cmd/old_attempt_v_001.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/m44_cmd/*.fits

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ─────────────────────────────────────────
# Standard BVRI configuration: Slot 1=L, 2=V, 3=B, 4=R, 5=I
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 7. Unpark and slew to wrong position (Polaris) ────────────────────
unpark_telescope
sleep 1
# Point at Polaris - nearly 70 degrees away from M44
slew_to_coordinates 2.530 89.264
wait_for_slew_complete 20
echo "Telescope at Polaris (wrong). Agent must find M44."

# ── 8. Reset CCD ──────────────────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the observing plan document ─────────────────────────────
cat > /home/ga/Documents/m44_observing_plan.txt << 'EOF'
============================================================
 OPEN CLUSTER PHOTOMETRY — OBSERVING PLAN
 PI: Dr. K. Ivanova, Stellar Populations Group
 Observer: Graduate Student
 Date Prepared: Current
============================================================

TARGET:
  Name:        M44 (NGC 2632, Praesepe, Beehive Cluster)
  Type:        Open Cluster in Cancer
  RA (J2000):  08h 40m 24s
  Dec (J2000): +19° 40' 00"
  Distance:    ~186 pc (Hipparcos/Gaia)
  Age:         ~600-700 Myr
  Reddening:   E(B-V) = 0.027 mag (nearly negligible)

SCIENTIFIC GOAL:
  Construct a B vs (B-V) color-magnitude diagram for thesis
  proposal Figure 3. CMD will be compared against PARSEC
  isochrones at [Fe/H] = +0.16 and age = 650 Myr.

FILTER CONFIGURATION:
  B-band (Johnson B): Filter wheel slot 3
    - Exposure time: 20 seconds per frame
    - Minimum frames: 8
    - Upload directory: /home/ga/Images/m44_cmd/B/

  V-band (Johnson V): Filter wheel slot 2
    - Exposure time: 15 seconds per frame
    - Minimum frames: 8
    - Upload directory: /home/ga/Images/m44_cmd/V/

  NOTE: Take all B-band frames first, then switch to V-band.
  This minimizes filter wheel wear and ensures consistent
  atmospheric conditions within each filter set.

ADDITIONAL REQUIREMENTS:
  1. Capture a sky survey view of the M44 field:
     Save to: /home/ga/Images/m44_cmd/m44_sky_view.png
     Use: bash ~/capture_sky_view.sh /home/ga/Images/m44_cmd/m44_sky_view.png 1.5

  2. Write observation summary report:
     Save to: /home/ga/Documents/m44_cmd_report.txt

REPORT FORMAT:
  The report must contain:
  - HEADER: Target name, coordinates, cluster parameters
  - OBSERVATIONS: For each filter — filter name, slot number,
    exposure time, number of frames captured, upload directory
  - CMD NOTES: Brief note on expected CMD features for a
    ~650 Myr cluster (main sequence turnoff, red giant clump)
  - QUALITY: Any notes on conditions or issues

IMPORTANT: Previous partial data may exist in the m44_cmd
directory from an earlier attempt. Do NOT use old files.
Only frames captured during THIS session are valid.
============================================================
EOF

chown ga:ga /home/ga/Documents/m44_observing_plan.txt

# ── 10. Ensure KStars is running ───────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Record initial state ───────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Observing plan at ~/Documents/m44_observing_plan.txt"
echo "Target: M44 (RA 08h 40m 24s, Dec +19d 40m)"
echo "Telescope at Polaris - agent must slew to M44 field"