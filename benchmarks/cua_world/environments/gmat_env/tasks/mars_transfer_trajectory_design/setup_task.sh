#!/bin/bash
set -euo pipefail

echo "=== Setting up mars_transfer_trajectory_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output/*
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Create requirements document
cat > /home/ga/Desktop/mars_mission_requirements.txt << 'REQEOF'
========================================
MARS ORBITER MISSION - PRELIMINARY TRAJECTORY DESIGN
Requirements Specification v1.0
========================================

MISSION: Mars-Scout Pathfinder (MSP-1)
LAUNCH VEHICLE: Atlas V 401 (standard GTO-class injection)
TARGET: Mars orbit insertion

DEPARTURE PARAMETERS:
  Parking Orbit: 200 km circular, 28.5 deg inclination (Cape Canaveral)
  Launch Epoch: 14 Jul 2026 12:00:00.000 UTC (nominal center of window)
  Departure Type: Direct TMI from parking orbit (single impulse)

SPACECRAFT:
  Dry Mass: 1200 kg
  Fuel Mass: 800 kg (bipropellant, Isp=320s — for reference only; use impulsive burn)
  Coordinate System: EarthMJ2000Eq at departure
  Drag/SRP: Negligible in heliocentric cruise (ignore)

ARRIVAL CONSTRAINTS:
  Target Body: Mars
  Closest Approach: Must achieve < 500,000 km from Mars center
  Preferred: < 50,000 km (for orbit insertion feasibility)
  Arrival Epoch: Expected ~180-300 days after departure

HELIOCENTRIC CRUISE:
  Central Body: Sun
  Force Model: Sun gravity + Earth, Mars, Jupiter as point masses (minimum)
  Coordinate System: SunMJ2000Eq
  Propagator: Prince-Dormand 78 or RungeKutta89 recommended

TARGETING APPROACH:
  Use DifferentialCorrector to vary TMI burn components
  Achieve Mars closest approach distance target
  Initial guess for TMI DeltaV: ~3.6 km/s (prograde from parking orbit)

EXPECTED PARAMETER RANGES (for validation):
  C3: 6 - 20 km^2/s^2
  TMI DeltaV: 3.4 - 4.5 km/s (from 200 km LEO)
  Time of Flight: 180 - 350 days (Type I transfer)
  Mars CA: < 500,000 km (targeting goal)

OUTPUT REQUIREMENTS:
  Save script to: ~/GMAT_output/mars_transfer.script
  Save results to: ~/GMAT_output/mars_transfer_results.txt
  Results must include: C3_km2s2, TMI_DeltaV_kms, TOF_days, Mars_CA_km
========================================
REQEOF

chown ga:ga /home/ga/Desktop/mars_mission_requirements.txt

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

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