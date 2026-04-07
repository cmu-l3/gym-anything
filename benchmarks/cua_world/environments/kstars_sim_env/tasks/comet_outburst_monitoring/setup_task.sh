#!/bin/bash
set -e
echo "=== Setting up comet_outburst_monitoring task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/comets
rm -f /home/ga/Documents/comet_alert.txt
rm -f /home/ga/Documents/icq_report_29P.txt
rm -f /tmp/task_result.json

# ── 3. Create directory structure ─────────────────────────────────────
mkdir -p /home/ga/Images/comets/29P/R
mkdir -p /home/ga/Images/comets/29P/V
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/comets
chown -R ga:ga /home/ga/Documents

# ── 4. ERROR INJECTION: Seed stale FITS files ─────────────────────────
# These files predate the session (Jan 2024 timestamp) and should not count
touch -t 202401011200 /home/ga/Images/comets/29P/R/old_obs_001.fits 2>/dev/null || true
touch -t 202401011200 /home/ga/Images/comets/29P/V/old_obs_002.fits 2>/dev/null || true
chown ga:ga /home/ga/Images/comets/29P/R/old_obs_001.fits
chown ga:ga /home/ga/Images/comets/29P/V/old_obs_002.fits

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel for standard photometric slots ──────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 7. Unpark telescope and slew to WRONG position ────────────────────
unpark_telescope
sleep 1
# Point at Polaris (RA ~2.5h, Dec ~+89°) - far from target
slew_to_coordinates 2.5300 89.2641
wait_for_slew_complete 20
echo "Telescope at Polaris (wrong position). Agent must slew to 29P."

# ── 8. Set CCD to neutral defaults ────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the outburst alert document ─────────────────────────────
cat > /home/ga/Documents/comet_alert.txt << 'EOF'
==========================================================
COBS OUTBURST ALERT — PRIORITY: HIGH
Comet Observation Database (COBS) Network
==========================================================

TARGET: 29P/Schwassmann-Wachmann 1
STATUS: CONFIRMED OUTBURST — Δm ≈ 4.0 mag

Date of outburst detection: 2024-11-18.5 UT
Reported by: J. Gonzalez (Spain), M. Mattiazzo (Australia)

CURRENT EPHEMERIS (J2000, epoch 2024-11-19.0 UT):
  RA:  06h 15m 22s
  Dec: +23° 04' 18"
  Estimated visual magnitude: 12.5 (quiescent: ~16.5)
  Heliocentric distance: 5.97 AU
  Geocentric distance: 5.41 AU

REQUESTED OBSERVATIONS:
  1. R-band CCD photometry (for Af-rho dust measurement)
     - Filter: R-band (filter wheel slot 4)
     - Exposure: 60 seconds per frame
     - Minimum frames: 5
     - Upload to: /home/ga/Images/comets/29P/R/

  2. V-band CCD photometry (for total magnitude)
     - Filter: V-band (filter wheel slot 2)
     - Exposure: 45 seconds per frame
     - Minimum frames: 3
     - Upload to: /home/ga/Images/comets/29P/V/

  3. Widefield sky capture (for finding chart)
     - Use capture_sky_view.sh with FOV ≥ 1.0°
     - Save to: /home/ga/Images/comets/29P/finding_chart.png

REPORT REQUIREMENTS:
  Submit observation report in ICQ format to:
    /home/ga/Documents/icq_report_29P.txt

  ICQ Format Reference:
    Line 1: IIIYYYYMnL  (III=comet designation, YYYY=year, Mn=month, L=day fraction)
    Required fields: total magnitude (m1), coma diameter (Dia), 
    degree of condensation (DC, scale 0-9), instrument aperture,
    f-ratio, observer name, method code.

    Header lines should include:
      OBS: [Observer name]
      TEL: [Telescope description]
      COM: [Comments about outburst status]

  For this outburst, estimate:
    - Total magnitude (m1): ~12.5
    - Coma diameter: ~0.3 arcminutes (compact due to heliocentric distance)
    - Degree of condensation (DC): 6 (moderately condensed outburst coma)

BACKGROUND:
  29P/Schwassmann-Wachmann 1 is a 60-km centaur in a near-circular
  orbit at ~6 AU. It exhibits CO-driven outbursts 7-8 times per year,
  making it the most active comet at large heliocentric distances.
  First discovered in 1927 by A. Schwassmann and A.A. Wachmann at
  Hamburg Observatory.

NOTE: Previous session data may exist in the upload directories.
  Only NEW frames taken during THIS session should be reported.
==========================================================
EOF

chown ga:ga /home/ga/Documents/comet_alert.txt
echo "Alert document written to /home/ga/Documents/comet_alert.txt"

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

# ── 11. Record initial state and screenshot ───────────────────────────
INITIAL_FITS=$(find /home/ga/Images/comets -name "*.fits" 2>/dev/null | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="