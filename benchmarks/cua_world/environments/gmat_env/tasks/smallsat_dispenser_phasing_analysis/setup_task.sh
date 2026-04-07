#!/bin/bash
set -euo pipefail

echo "=== Setting up smallsat_dispenser_phasing_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/dispenser_deployment_spec.txt
rm -f /home/ga/Documents/missions/dispenser_mission.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create dispenser specification document
cat > /home/ga/Desktop/dispenser_deployment_spec.txt << 'SPECEOF'
================================================================
 CUBESAT DISPENSER DEPLOYMENT KINEMATICS SPECIFICATION
 Mission: Transporter-X Rideshare
 Date: 2025-10-01
================================================================

1. LAUNCH VEHICLE INSERTION ORBIT (INITIAL STATE FOR ALL SATS)
   Orbit Type:         Circular Sun-Synchronous
   Epoch:              01 Jan 2026 12:00:00.000 UTCG
   Semi-Major Axis:    6871.14 km   (altitude ~500 km)
   Eccentricity:       0.0
   Inclination:        97.4 deg
   RAAN:               0.0 deg
   Argument of Perigee: 0.0 deg
   True Anomaly:       0.0 deg
   Coordinate System:  EarthMJ2000Eq

2. SPACECRAFT PROPERTIES (IDENTICAL FOR ALL)
   Mass:               10.0 kg

3. DISPENSER EJECTION VELOCITIES
   Mechanism: Spring pushers aligned with LV velocity vector (Prograde / Local V direction).
   Ejection occurs instantly at Epoch.
   
   Sat A:  +0.5 m/s
   Sat B:  +1.0 m/s
   Sat C:  +1.5 m/s
   Sat D:  +2.0 m/s

4. PROPAGATION REQUIREMENTS
   Duration:           30.0 Days
   Force Model:        Earth 8x8 Gravity only (No Drag - assume pristine vacuum for kinematic baseline)

================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/dispenser_deployment_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/dispenser_deployment_spec.txt ==="