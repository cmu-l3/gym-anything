#!/bin/bash
set -e
echo "=== Setting up pointing model construction task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/pointing_model
rm -f /home/ga/Documents/pointing_calibration_spec.txt
rm -f /home/ga/Documents/pointing_model.dat
rm -f /tmp/task_result.json

# 3. Ensure INDI is running and devices connected
ensure_indi_running
sleep 2
connect_all_devices
sleep 2

# 4. Park the telescope (Starting state constraint)
indi_setprop "Telescope Simulator.TELESCOPE_PARK.PARK=On" 2>/dev/null || true
sleep 3

# 5. Create pointing model image directory structure and seed stale files
mkdir -p /home/ga/Images/pointing_model/vega
mkdir -p /home/ga/Images/pointing_model/arcturus

# ERROR INJECTION: Seed stale FITS files (from a previous invalidated run)
echo "SIMPLE  =                    T" > /home/ga/Images/pointing_model/vega/old_pointing_001.fits
echo "SIMPLE  =                    T" > /home/ga/Images/pointing_model/arcturus/old_pointing_001.fits
touch -t 202401150300.00 /home/ga/Images/pointing_model/vega/old_pointing_001.fits
touch -t 202401150305.00 /home/ga/Images/pointing_model/arcturus/old_pointing_001.fits

chown -R ga:ga /home/ga/Images/pointing_model

# 6. Create the specification document
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/pointing_calibration_spec.txt << 'SPEC'
===============================================================
  OBSERVATORY MAINTENANCE REQUEST — POINTING MODEL REBUILD
  Date: 2024-11-20
  Requestor: Dr. Patricia Hartigan, Observatory Director
  Priority: HIGH — Must complete before tonight's science run
===============================================================

REASON FOR RECALIBRATION:
  The primary mirror was removed on 2024-11-15 for recoating
  (fresh aluminum deposition at Optical Mechanics Inc.). After
  reinstallation and collimation on 2024-11-19, the existing
  pointing model is invalidated. A full pointing run is required
  before any science observations can proceed.

  NOTE: There are stale FITS files from the January 2024 pointing
  run in some directories. These are from the old model and should
  be ignored — do not count them as part of this calibration.

PROCEDURE:
  1. Unpark the telescope
  2. For each reference star below, in any order:
     a. Set CCD upload directory to:
        /home/ga/Images/pointing_model/<star_name_lowercase>/
        (e.g., /home/ga/Images/pointing_model/polaris/)
     b. Slew telescope to the star's coordinates (Track mode)
     c. Wait for slew to complete
     d. Take one 5-second LIGHT frame exposure (no filter / Luminance)
  3. After all 8 stars are observed, produce the TPoint input file
  4. Capture a final sky view for the observation log

CCD SETTINGS:
  - Frame type: LIGHT
  - Exposure: 5 seconds
  - Filter: Luminance (slot 1) or no filter change needed
  - Upload mode: Local
  - Upload prefix: ptmodel_

REFERENCE STARS (8 targets, well-distributed across sky):

  #  Star         Constellation      RA (J2000)      Dec (J2000)     V mag
  ─  ─────────    ──────────────     ──────────      ───────────     ─────
  1  Polaris      Ursa Minor         02h 31m 49s     +89° 15' 51"    1.98
  2  Capella      Auriga             05h 16m 41s     +45° 59' 53"    0.08
  3  Regulus      Leo                10h 08m 22s     +11° 58' 02"    1.36
  4  Arcturus     Boötes             14h 15m 40s     +19° 10' 57"   -0.05
  5  Vega         Lyra               18h 36m 56s     +38° 47' 01"    0.03
  6  Altair       Aquila             19h 50m 47s     +08° 52' 06"    0.76
  7  Deneb        Cygnus             20h 41m 26s     +45° 16' 49"    1.25
  8  Fomalhaut    Piscis Austrinus   22h 57m 39s     -29° 37' 20"    1.16

  Decimal equivalents for INDI commands:
  1  Polaris      RA=2.5303    Dec=+89.2642
  2  Capella      RA=5.2781    Dec=+45.9981
  3  Regulus      RA=10.1394   Dec=+11.9672
  4  Arcturus     RA=14.2611   Dec=+19.1825
  5  Vega         RA=18.6156   Dec=+38.7836
  6  Altair       RA=19.8464   Dec=+8.8683
  7  Deneb        RA=20.6906   Dec=+45.2803
  8  Fomalhaut    RA=22.9608   Dec=-29.6222

OUTPUT FILE:
  Path: /home/ga/Documents/pointing_model.dat
  Format: TPoint standard input format

  Example:
    ! TPoint Pointing Model Data
    ! Observatory: Simulator Observatory
    ! Date: 2024-11-20
    ! Instrument: 200mm f/3.75 Newtonian + CCD Simulator
    ! Operator: [agent]
    :EQUAT
    :SYM
    ! Star_Name  RA_commanded(h m s)  Dec_commanded(d m s)  RA_observed(h m s)  Dec_observed(d m s)
    Polaris     02 31 49  +89 15 51  02 31 49  +89 15 51
    Capella     05 16 41  +45 59 53  05 16 41  +45 59 53
    ...
    END

  NOTE: Since this is a simulator, commanded and observed coordinates
  will be identical. In a real system, plate-solving would determine
  observed coordinates. For this run, record the commanded coordinates
  in both columns.

FINAL STEP:
  Capture a sky view at the last observed position:
    bash ~/capture_sky_view.sh ~/Images/pointing_model/final_sky.png
SPEC
chown ga:ga /home/ga/Documents/pointing_calibration_spec.txt

# 7. Ensure KStars is running
ensure_kstars_running
sleep 3
maximize_kstars
focus_kstars
sleep 1

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Pointing model task setup complete ==="
echo "Telescope: PARKED at home position"
echo "Spec document: ~/Documents/pointing_calibration_spec.txt"