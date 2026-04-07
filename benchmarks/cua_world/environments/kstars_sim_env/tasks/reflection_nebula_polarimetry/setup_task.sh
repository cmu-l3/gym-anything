#!/bin/bash
set -e
echo "=== Setting up reflection_nebula_polarimetry task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/polarimetry
rm -f /home/ga/Documents/polarimetry_request.txt
rm -f /home/ga/Documents/stokes_observation_log.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ──────────────────────────────────────────────
mkdir -p /home/ga/Images/polarimetry/M78/angle_000
mkdir -p /home/ga/Images/polarimetry/M78/angle_045
mkdir -p /home/ga/Images/polarimetry/M78/angle_090
mkdir -p /home/ga/Images/polarimetry/M78/angle_135
mkdir -p /home/ga/Documents

# ── 4. ERROR INJECTION: Seed decoy files in angle_000 ─────────────────
# These have old timestamps and must not count towards the agent's work
touch -t 202401010000 /home/ga/Images/polarimetry/M78/angle_000/old_polar_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/polarimetry/M78/angle_000/old_polar_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/polarimetry/M78/angle_000/old_polar_003.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/polarimetry
chown -R ga:ga /home/ga/Documents

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel for polarimetry ─────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=Pol_000" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=Pol_045" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=Pol_090" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Pol_135" 2>/dev/null || true
sleep 1

# ── 7. Unpark and slew to WRONG position ──────────────────────────────
unpark_telescope
sleep 1
# Point at Sirius (RA 06:45, Dec -16:42) - entirely wrong field
slew_to_coordinates 6.7525 -16.7161
wait_for_slew_complete 20
echo "Telescope pointed at Sirius. Agent must find M78."

# ── 8. Reset CCD to defaults ──────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the observing request document ──────────────────────────
cat > /home/ga/Documents/polarimetry_request.txt << 'EOF'
OBSERVING REQUEST: LINEAR POLARIMETRY OF M78
=============================================
Prepared by: Dr. E. Vance, Interstellar Medium Research Group

SCIENTIFIC OBJECTIVE
--------------------
Map the magnetic field geometry within the M78 reflection nebula by
deriving the Stokes Q and U parameters from polarized scattered light.

TARGET
------
Object: M78 (Messier 78 / NGC 2068)
Type: Reflection Nebula
Right Ascension: 05h 46m 46.7s
Declination:    +00d 00m 50s (J2000)
Constellation: Orion

INSTRUMENT CONFIGURATION
------------------------
To measure linear polarization, we need exposures through polaroid
filters oriented at four specific angles.

Filter Wheel Mappings:
  Slot 2 = Pol_000 (0 degrees)
  Slot 3 = Pol_045 (45 degrees)
  Slot 4 = Pol_090 (90 degrees)
  Slot 5 = Pol_135 (135 degrees)

OBSERVING SEQUENCE
------------------
For each of the four polarization angles (000, 045, 090, 135), you must:
1. Select the correct filter slot.
2. Set the CCD upload directory to: /home/ga/Images/polarimetry/M78/angle_XXX/
   (Replace XXX with the current angle: 000, 045, 090, or 135)
3. Capture at least 3 LIGHT frames.
4. Exposure time must be 120 seconds per frame.

CONTEXT IMAGE
-------------
After the polarimetry sequence, capture a wider field context image:
bash ~/capture_sky_view.sh /home/ga/Images/polarimetry/M78/m78_context.png 1.0 --palette cool

OBSERVATION LOG
---------------
Please leave a summary report at /home/ga/Documents/stokes_observation_log.txt
Include:
- The target name (M78)
- Confirmation that all four angles (000, 045, 090, 135) were observed
- The number of successful frames captured for each angle
EOF

chown ga:ga /home/ga/Documents/polarimetry_request.txt

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
INITIAL_FITS=$(find /home/ga/Images/polarimetry 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Observing request at ~/Documents/polarimetry_request.txt"