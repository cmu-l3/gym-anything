#!/bin/bash
set -euo pipefail

echo "=== Setting up repeat_groundtrack_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/earthmapper3_orbit_requirements.txt
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create requirements document
cat > /home/ga/Desktop/earthmapper3_orbit_requirements.txt << 'REQEOF'
================================================================
EARTHMAPPER-3 ORBIT DESIGN REQUIREMENTS
Preliminary Design Review (PDR) Input Document
Document: EM3-ORB-REQ-001 Rev A
Date: 2025-09-15
================================================================

1. MISSION OVERVIEW
   EarthMapper-3 is a high-resolution multispectral imaging satellite
   for agricultural monitoring, urban planning, and disaster response.
   The satellite requires systematic global coverage with predictable
   revisit intervals.

2. ORBIT TYPE
   Sun-synchronous, near-circular, repeat ground track orbit.

3. REPEAT CYCLE SPECIFICATION
   - Exact repeat period: 16 days
   - Revolutions per cycle: 233
   - This yields ~14.5625 revolutions per day
   - Daily nodal spacing at equator: ~24.63 degrees longitude

4. SUN-SYNCHRONOUS REQUIREMENT
   - Local Time of Ascending Node (LTAN): 22:30 (10:30 PM)
   - Equivalently, Local Time of Descending Node: 10:30 AM
   - RAAN precession must match Earth's mean motion around Sun
     (+0.9856 deg/day eastward)

5. ORBIT SHAPE
   - Eccentricity: < 0.002 (near-circular)
   - Frozen eccentricity preferred if achievable

6. SPACECRAFT PARAMETERS
   - DryMass: 680 kg
   - DragArea: 5.5 m^2
   - Cd (drag coefficient): 2.2
   - SRPArea: 6.0 m^2
   - Cr (reflectivity coefficient): 1.8

7. SIMULATION PARAMETERS
   - Epoch: 01 Mar 2026 00:00:00.000 UTC
   - Propagation duration: 16 days (one complete repeat cycle)
   - Force model: Earth gravity >= 10x10, atmospheric drag,
     solar radiation pressure, lunisolar third body
   - Coordinate system: EarthMJ2000Eq

8. VERIFICATION CRITERIA
   - After exactly 16 days of propagation, the sub-satellite
     longitude at the ascending equatorial crossing shall return
     to within 1.0 degree of the initial crossing longitude.
   - The RAAN precession rate shall be 0.9856 +/- 0.05 deg/day.

9. REFERENCE VALUES (from heritage Landsat-8 mission)
   Landsat-8 achieves a 16-day/233-rev repeat at:
   - Mean altitude: ~705 km
   - Inclination: ~98.2 degrees
   These values are FOR REFERENCE ONLY. The agent must compute
   the correct values for EarthMapper-3 from first principles
   using the repeat condition and sun-synchronous constraint.

10. DELIVERABLES
    - GMAT script: ~/GMAT_output/earthmapper3_orbit.script
    - Results report: ~/GMAT_output/groundtrack_design_results.txt
================================================================
REQEOF

chown ga:ga /home/ga/Desktop/earthmapper3_orbit_requirements.txt

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