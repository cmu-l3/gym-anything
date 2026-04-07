#!/bin/bash
set -euo pipefail

echo "=== Setting up cubesat_dragsail_deorbit task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/astrocube_spec.txt
rm -f /home/ga/Documents/missions/dragsail_mission.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/astrocube_spec.txt << 'SPECEOF'
=============================================================
AstroCube-1 Mission Specification & Disposal Requirements
=============================================================

SATELLITE PARAMETERS
Initial Orbit: 625 km circular
Initial SMA: 7003.14 km (Earth Eq Radius 6371.14 + 625)
Inclination: 97.5 deg
Epoch: 01 Jan 2026 12:00:00 UTC
Dry Mass: 12.0 kg
Coefficient of Drag (Cd): 2.2

OPERATIONAL PHASE (Year 1)
Duration: 365 days
Configuration: Drag sail stowed
Stowed Drag Area: 0.06 m^2

DISPOSAL PHASE (Year 2+)
Trigger: Deployed immediately after 365 days of operations
Configuration: Drag sail deployed
Deployed Drag Area: 2.5 m^2 (Based on DragNet-2.5 standard)
Target: Atmospheric re-entry (120 km altitude)
Constraint: Total mission time (operations + disposal) MUST be < 5 years (1825 days)

ENVIRONMENTAL MODEL
Atmosphere: JacchiaRoberts or MSISE
Solar Flux (F10.7): 130
Solar Flux Average (F10.7A): 130
Geomagnetic Index (Kp/MagneticIndex): 3

REPORTING REQUIREMENTS
Write a report to ~/GMAT_output/dragsail_compliance_report.txt containing:
- altitude_at_deployment_km (altitude after exactly 365 days)
- total_lifetime_days (total elapsed days from epoch to 120 km)
- compliance_status (COMPLIANT if < 1825 days, else NON_COMPLIANT)
=============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/astrocube_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/astrocube_spec.txt ==="