#!/bin/bash
set -e
echo "=== Setting up asteroid_lightcurve_photometry task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/lightcurves
rm -f /home/ga/Documents/lightcurve_plan.txt
rm -f /home/ga/Documents/nysa_lightcurve.txt
rm -f /tmp/task_result.json

# 3. Create root directories (agent must create the specific target dir)
mkdir -p /home/ga/Images/lightcurves
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/lightcurves
chown -R ga:ga /home/ga/Documents

# 4. Start INDI and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 6. Unpark and slew to wrong target (Vega)
unpark_telescope
sleep 1
# Vega: RA 18h 36m 56s = 18.6156h, Dec +38° 47' 01" = +38.7836°
slew_to_coordinates 18.6156 38.7836
wait_for_slew_complete 20
echo "Telescope at Vega (wrong target). Agent must find (44) Nysa."

# 7. Set filter to slot 3 (wrong - should be 1) and reset CCD
indi_setprop "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=3" 2>/dev/null || true
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create the observing plan document
cat > /home/ga/Documents/lightcurve_plan.txt << 'PLANEOF'
ASTEROID LIGHTCURVE OBSERVATION PLAN
=====================================
Minor Planet Bulletin Collaborative Program
Session ID: LC-2024-0315

TARGET:
  Object: (44) Nysa
  Type: S-type main-belt asteroid
  Predicted V mag: 9.7
  Rotation period (literature): 6.4214 h

EPHEMERIS (J2000, epoch of observation):
  RA:  18h 32m 15.0s
  Dec: -25d 08' 42.0"
  Motion: 0.35 "/min (sidereal tracking acceptable)

INSTRUMENT CONFIGURATION:
  Filter: Luminance / Clear (filter slot 1)
    NOTE: Unfiltered maximizes SNR for differential photometry of
    asteroids. Do NOT use narrowband or color filters.
  Exposure: 60 seconds per frame
  Frame type: LIGHT
  Binning: 1x1 (default)

SEQUENCE REQUIREMENTS:
  Minimum frames: 15 consecutive exposures
  Cadence: Back-to-back (no delays between exposures)
  Upload directory: /home/ga/Images/lightcurves/nysa/

SKY CAPTURE:
  After the imaging sequence, capture a sky view of the field
  for documentation: bash ~/capture_sky_view.sh

OUTPUT:
  Produce an ALCDEF-format lightcurve data file at:
    /home/ga/Documents/nysa_lightcurve.txt

  ALCDEF format reference (v2.0):
    - STARTMETADATA / ENDMETADATA block with object info
    - Required metadata fields: OBJECTNUMBER, OBJECTNAME,
      SESSIONDATE, FILTER, LTCTYPE, OBJECTRA, OBJECTDEC,
      STANDARD=ALCDEF
    - STARTDATA / ENDDATA block with measurements
    - Each data line: DATA=JD|MAG|MAGERR
    - Use placeholder magnitudes (e.g., 9.70|0.03) since
      this is a simulation -- real reduction would extract
      differential photometry from the FITS files.
    - Include one DATA line per exposure taken.

COMPARISON STARS:
  Use field stars for differential photometry (post-processing).
  Comparison star catalog: APASS DR10 (for future reduction).

NOTES:
  - (44) Nysa was discovered in 1857 by H. Goldschmidt
  - It is the brightest member of the Nysa family (~19,000 members)
  - Its shape is highly elongated (a/b ratio ~1.6), producing
    a lightcurve amplitude of ~0.5 magnitudes
PLANEOF

chown ga:ga /home/ga/Documents/lightcurve_plan.txt

# 9. Ensure KStars is running
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 10. Record initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="