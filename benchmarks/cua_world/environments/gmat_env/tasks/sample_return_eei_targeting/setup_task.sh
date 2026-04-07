#!/bin/bash
set -euo pipefail

echo "=== Setting up sample_return_eei_targeting task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/stardust2_tcm_spec.txt
rm -f /home/ga/Documents/missions/tcm4_targeting.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write spec document to Desktop
cat > /home/ga/Desktop/stardust2_tcm_spec.txt << 'SPECEOF'
=======================================================
  STARDUST-2 SAMPLE RETURN: TCM-4 SPECIFICATION
  Flight Dynamics Facility
  Date: 2026-09-07
=======================================================

MISSION CONTEXT
  The Stardust-2 sample return capsule is on a hyperbolic
  Earth-return trajectory. Trajectory Correction Maneuver 4
  (TCM-4) must be executed at the current epoch to precisely
  target the Earth Entry Interface (EEI).

INITIAL STATE (Pre-TCM)
  Spacecraft: Stardust2_SRC
  Epoch: 10 Sep 2026 00:00:00.000 UTCG
  Coordinate System: EarthMJ2000Eq
  State Type: Cartesian
    X  =  280000.0 km
    Y  = -150000.0 km
    Z  =  80000.0 km
    VX = -1.8000 km/s
    VY =  1.0000 km/s
    VZ = -0.5000 km/s

  Dry Mass: 250 kg
  Coefficient of Drag (Cd): 2.2
  Drag Area: 1.5 m^2

TCM-4 MANEUVER
  Type: Impulsive Burn
  Epoch: Same as Initial State
  Coordinate System: VNB (Velocity-Normal-Binormal) or Local

TARGETING REQUIREMENTS (ENTRY INTERFACE)
  The capsule must reach Earth Entry Interface (EEI) defined as:
    Stopping Condition: Earth.Altitude = 120.0 km

  At the EEI point, the trajectory must strictly satisfy:
    1. Radius of Periapsis (RadPer) = 6418.14 km
       (This ensures an effective 40 km theoretical perigee
        for proper atmospheric capture without burn-up).
    2. Inclination (INC) = 45.0 deg
       (Required for alignment with the Utah Test and Training Range).

FORCE MODEL
  Central Body: Earth
  Gravity: Point Mass is sufficient, or JGM-2
  Third Bodies: Luna, Sun (Recommended for accuracy)

OUTPUT REQUIREMENTS
  Generate a report at ~/GMAT_output/tcm4_targeting_results.txt
  containing EXACTLY these lines:
    Achieved_RadPer_km: <value>
    Achieved_INC_deg: <value>
    Total_Required_DeltaV_mps: <value>
=======================================================
SPECEOF

chown ga:ga /home/ga/Desktop/stardust2_tcm_spec.txt

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

echo "=== Task Setup Complete: Spec document at ~/Desktop/stardust2_tcm_spec.txt ==="