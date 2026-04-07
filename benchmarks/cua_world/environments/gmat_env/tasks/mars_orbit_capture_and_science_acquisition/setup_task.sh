#!/bin/bash
set -euo pipefail

echo "=== Setting up mars_orbit_capture_and_science_acquisition task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts and ensure directories exist
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/mars_capture_spec.txt
rm -f /home/ga/GMAT_output/mars_capture.script
rm -f /home/ga/GMAT_output/mars_capture_results.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the mission specification document
cat > /home/ga/Desktop/mars_capture_spec.txt << 'SPECEOF'
================================================================
  MARS ATMOSPHERIC & CLIMATE EXPLORER (MACE)
  MARS ORBIT ACQUISITION — MISSION SPECIFICATION
================================================================

1. SPACECRAFT APPROACH STATE (Mars-centered MJ2000Eq)
   Central Body: Mars
   Coordinate System: Create a custom CoordinateSystem with
                      Origin = Mars, Axes = MJ2000Eq
   Epoch: 15 Feb 2027 06:00:00.000 UTC
   SMA:   -6100.0 km        (hyperbolic orbit, negative SMA)
   ECC:    1.606
   INC:   93.0 deg
   RAAN:  45.0 deg
   AOP:    0.0 deg
   TA:   340.0 deg           (spacecraft is approaching periapsis)

   Note: Periapsis altitude is approximately 300 km above Mars
   surface (Mars equatorial radius = 3396.2 km).

2. SPACECRAFT PROPERTIES
   Dry Mass:     450 kg
   SRP Area:      12.0 m^2
   Cr:             1.35

3. PROPULSION SYSTEM
   Type: Bipropellant with ChemicalTank
   Fuel Mass:    500 kg
   Isp:          321 s
   GravitationalAccel: 9.81 m/s^2
   Use ImpulsiveBurn with DecrementMass = true

4. TARGET ORBITS

   Post-MOI Capture Orbit:
     Periapsis altitude:  300 km
     Apoapsis altitude:   30,000 km
     SMA:                 18,546 km
     ECC:                 0.8007
     INC:                 90.0 deg   <-- NOTE: Plane change
                                         from 93 deg to 90 deg

   Post-PRM Science Orbit:
     Periapsis altitude:  300 km
     Apoapsis altitude:   10,000 km
     SMA:                 8,546 km
     ECC:                 0.5676
     INC:                 90.0 deg

5. FORCE MODEL REQUIREMENTS
   Central Body:  Mars
   Gravity:       Mars50c, Degree >= 10, Order >= 10
   Third-Body:    Sun (point mass)
   SRP:           On
   Drag:          Off (negligible at 300 km Mars altitude)

6. BURN STRATEGY

   MOI Burn (at Mars periapsis):
     Propagate spacecraft to Mars periapsis first.
     This is a combined retrograde capture and plane change burn.
     ImpulsiveBurn in Local VNB frame (Origin = Mars):
       Element1 = retrograde delta-V component (negative)
       Element2 = normal/cross-track component (negative, to
                  decrease inclination from 93 to 90 deg)
     Use DifferentialCorrector:
       Vary: Element1 and Element2
       Achieve: Post-burn SMA = 18546.0 km AND INC = 90.0 deg

   PRM Burn (at next Mars periapsis):
     Propagate one full orbit to return to Mars periapsis.
     Pure retrograde burn to lower apoapsis.
     ImpulsiveBurn in Local VNB frame (Origin = Mars):
       Element1 = retrograde delta-V (negative)
     Use DifferentialCorrector:
       Vary: Element1
       Achieve: Post-burn SMA = 8546.0 km

7. STABILITY VERIFICATION
   After PRM, propagate 30 Earth days under the same force model.
   Monitor periapsis altitude. If it stays above 250 km, report
   Stability_30day: PASS. Otherwise report FAIL.

8. OUTPUT REQUIREMENTS
   GMAT Script:  ~/GMAT_output/mars_capture.script
   Results File: ~/GMAT_output/mars_capture_results.txt

   Results file must contain these keys (one per line):
     MOI_DeltaV_mps: <total delta-V magnitude of MOI in m/s>
     MOI_Fuel_kg: <fuel consumed by MOI in kg>
     MOI_PostBurn_SMA_km: <post-MOI SMA in km>
     MOI_PostBurn_ECC: <post-MOI eccentricity>
     MOI_PostBurn_INC_deg: <post-MOI inclination in degrees>
     PRM_DeltaV_mps: <delta-V of PRM in m/s>
     PRM_Fuel_kg: <fuel consumed by PRM in kg>
     PRM_PostBurn_SMA_km: <post-PRM SMA in km>
     PRM_PostBurn_ECC: <post-PRM eccentricity>
     PRM_PostBurn_INC_deg: <post-PRM inclination in degrees>
     Total_DeltaV_mps: <total delta-V for both burns>
     Remaining_Fuel_kg: <fuel remaining after both burns>
     Stability_30day: PASS or FAIL

================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/mars_capture_spec.txt

# 4. Launch GMAT
echo "Launching GMAT..."
launch_gmat ""

echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 60)

if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="
