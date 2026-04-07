#!/bin/bash
set -e
echo "=== Setting up eb_minimum_timing task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/eb_timing
rm -f /home/ga/Documents/eb_timing_alert.txt
rm -f /home/ga/Documents/algol_oc_report.txt
rm -f /tmp/task_result.json

# ── 3. Create root directory (agent must create algol subdirectory) ──
mkdir -p /home/ga/Images/eb_timing
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/eb_timing
chown -R ga:ga /home/ga/Documents

# ── 4. Ensure INDI is running and connected ───────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel for BVRI ────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark and slew to WRONG position (Vega) ───────────────────────
unpark_telescope
sleep 1
# Point at Vega (summer sky) - entirely wrong position for Algol (winter sky)
slew_to_coordinates 18.6156 38.7837
wait_for_slew_complete 20
echo "Telescope at Vega (wrong). Agent must slew to Algol."

# ── 7. Reset CCD to defaults ──────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the timing alert document ───────────────────────────────
cat > /home/ga/Documents/eb_timing_alert.txt << 'EOF'
========================================================
  AAVSO ECLIPSING BINARY SECTION — TIMING ALERT #2024-047
========================================================

PRIORITY: HIGH
DATE ISSUED: 2024-12-15

TARGET: Algol (Beta Persei, HD 19356)
TYPE: EA/SD (Algol-type semi-detached eclipsing binary)
COORDINATES (J2000):
  RA:  03h 08m 10.13s
  Dec: +40d 57m 20.3s

COMPARISON STAR: Rho Persei (HD 19058)
  RA:  03h 05m 10.59s
  Dec: +38d 50m 25.2s
  V mag: 3.39

EPHEMERIS:
  Reference epoch (T0): HJD 2460700.500
  Orbital period (P):   2.8673075 days
  Predicted next minimum: HJD 2460703.367

PRIMARY ECLIPSE PARAMETERS:
  Eclipse depth:   1.3 mag (V: 2.12 -> 3.39)
  Eclipse duration: ~10 hours (contact I to IV)
  Minimum duration: ~2 hours (contact II to III)

OBSERVATION REQUIREMENTS:
  - Filter: V-band (Johnson V)
  - Exposure time: 10 seconds per frame
  - Cadence: continuous (no gaps between exposures)
  - Minimum frames: 20 (covering at least ingress or egress)
  - Upload directory: /home/ga/Images/eb_timing/algol/
  - Frame type: LIGHT

  Capture sky view of the target field with:
  bash ~/capture_sky_view.sh /home/ga/Images/eb_timing/algol/sky_verification.png 2.0

REPORTING:
  Submit an O-C timing report to:
    /home/ga/Documents/algol_oc_report.txt

  Report must include:
    - Object designation (Algol / Beta Per)
    - Predicted minimum JD from ephemeris
    - Observer code and method (CCD)
    - Filter used (V)
    - Number of observations in time series
    - Ephemeris reference (T0 and period)

  Use standard O-C reporting headers:
    #TYPE=EBMINIMA
    #OBJECT=<name>
    #RA=<ra_hours>
    #DEC=<dec_degrees>
    #FILTER=<filter>
    #METHOD=CCD
    #NOBS=<count>
    #PREDICTED_MIN_JD=<jd>
    #EPHEMERIS_T0=<jd>
    #EPHEMERIS_PERIOD=<days>
    #COMP_STAR=<name>
    #NOTES=<any notes>

SCIENTIFIC JUSTIFICATION:
  Algol's period has been monitored since Goodricke (1783). Recent
  analyses suggest a long-term period increase of ~3.4 sec/century
  attributed to mass transfer from the K-subgiant secondary to the
  B8 primary. Additional period modulations with a ~32-year cycle
  are attributed to the gravitational influence of Algol C. Continued
  high-precision timing is essential to disentangle these effects.
========================================================
EOF

chown ga:ga /home/ga/Documents/eb_timing_alert.txt
echo "Alert written to /home/ga/Documents/eb_timing_alert.txt"

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

# ── 10. Record initial state ───────────────────────────────────────────
INITIAL_FITS=$(find /home/ga/Images/eb_timing 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Timing Alert at ~/Documents/eb_timing_alert.txt"
echo "Target: Algol (Beta Persei)"
echo "Telescope currently parked at Vega - agent must navigate to Algol."