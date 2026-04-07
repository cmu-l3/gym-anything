#!/bin/bash
set -euo pipefail

echo "=== Setting up molniya_orbit_coverage_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/arcticlink_orbit_spec.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/arcticlink_orbit_spec.txt << 'SPECEOF'
============================================================
  ArcticLink Communications Satellite
  Orbit Requirements Specification
  Document: ARC-ORB-001 Rev A
  Date: 2025-01-15
============================================================

1. MISSION OVERVIEW

ArcticLink-1 is a broadband communications satellite designed
to provide high-speed internet coverage to Nordic and Arctic
regions (latitudes 55N to 85N). Geostationary satellites
provide poor coverage at these latitudes due to low elevation
angles. A highly elliptical orbit (HEO) solution is required.

2. ORBIT REQUIREMENTS

2.1 Orbit Type: Molniya (12-hour period)
2.2 Perigee Altitude: 500 +/- 100 km
2.3 Apogee: Must dwell over Northern Hemisphere
2.4 Argument of Perigee Stability: AOP must not drift more
    than 5 degrees over 30 days. This requires selection of
    the critical inclination at which J2 secular perturbation
    of argument of perigee vanishes (approximately 63.4 deg).
2.5 Orbital Period: 11.9 to 12.1 hours
2.6 Argument of Perigee: 270 deg (places apogee over Northern
    Hemisphere when combined with correct inclination)
2.7 RAAN: 60 deg (reference value for simulation)
2.8 True Anomaly at Epoch: 0 deg

3. SPACECRAFT PARAMETERS

3.1 Dry Mass: 1200 kg
3.2 Drag Coefficient (Cd): 2.2
3.3 Drag Area: 6.0 m^2
3.4 SRP Coefficient (Cr): 1.8
3.5 SRP Area: 12.0 m^2
3.6 Coordinate System: EarthMJ2000Eq

4. SIMULATION REQUIREMENTS

4.1 Epoch: 01 Mar 2025 00:00:00.000 UTC
4.2 Propagation Duration: 30 days minimum
4.3 Force Model: Must include Earth gravity harmonics
    (JGM-2, JGM-3, or EGM-96 with degree/order >= 4)
4.4 Include atmospheric drag (JacchiaRoberts or MSISE)
4.5 Include solar radiation pressure
4.6 Include lunar and solar point-mass gravity

5. DELIVERABLES

5.1 GMAT script: ~/GMAT_output/molniya_mission.script
5.2 Analysis report: ~/GMAT_output/molniya_analysis.txt
    The report must contain the following exactly labeled fields:
      SMA_km, ECC, INC_deg, AOP_initial_deg, AOP_final_deg,
      AOP_drift_deg, apogee_alt_km, perigee_alt_km, period_hours

6. ACCEPTANCE CRITERIA

6.1 AOP drift shall be less than 5 deg over 30 days
6.2 Apogee altitude shall be greater than 35000 km
6.3 Perigee altitude shall be between 400 and 600 km
6.4 Inclination shall be within 0.5 deg of 63.4 deg
6.5 Period shall be 12.0 +/- 0.1 hours
============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/arcticlink_orbit_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/arcticlink_orbit_spec.txt ==="