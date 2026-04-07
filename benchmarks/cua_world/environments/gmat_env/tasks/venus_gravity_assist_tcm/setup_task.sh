#!/bin/bash
set -euo pipefail

echo "=== Setting up Venus Gravity Assist TCM task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/Documents/missions/venus_tcm*.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the baseline GMAT script
# This script sets up a Venus encounter but misses the target parameters.
cat > /home/ga/Documents/missions/venus_tcm_baseline.script << 'GMATEOF'
%----------------------------------------
%---------- Coordinate Systems
%----------------------------------------
Create CoordinateSystem Venus_J2000;
GMAT Venus_J2000.Origin = Venus;
GMAT Venus_J2000.Axes = MJ2000Eq;

%----------------------------------------
%---------- Spacecraft
%----------------------------------------
Create Spacecraft SolarCruiser;
GMAT SolarCruiser.DateFormat = UTCGregorian;
GMAT SolarCruiser.Epoch = '15 Aug 2025 12:00:00.000';
GMAT SolarCruiser.CoordinateSystem = Venus_J2000;
GMAT SolarCruiser.DisplayStateType = Cartesian;

% Initial state pre-encounter (~500k km from Venus)
GMAT SolarCruiser.X = -500000.0;
GMAT SolarCruiser.Y = -300000.0;
GMAT SolarCruiser.Z = 200000.0;
GMAT SolarCruiser.VX = 3.5;
GMAT SolarCruiser.VY = 2.0;
GMAT SolarCruiser.VZ = -1.2;

GMAT SolarCruiser.DryMass = 850;
GMAT SolarCruiser.Cd = 2.2;
GMAT SolarCruiser.Cr = 1.8;
GMAT SolarCruiser.DragArea = 15;
GMAT SolarCruiser.SRPArea = 15;

%----------------------------------------
%---------- ForceModels
%----------------------------------------
Create ForceModel DeepSpaceFM;
GMAT DeepSpaceFM.CentralBody = Venus;
GMAT DeepSpaceFM.PrimaryBodies = {Venus};
GMAT DeepSpaceFM.PointMasses = {Sun};
GMAT DeepSpaceFM.Drag = None;
GMAT DeepSpaceFM.SRP = Off;
GMAT DeepSpaceFM.ErrorControl = RSSStep;

%----------------------------------------
%---------- Propagators
%----------------------------------------
Create Propagator DeepSpaceProp;
GMAT DeepSpaceProp.FM = DeepSpaceFM;
GMAT DeepSpaceProp.Type = RungeKutta89;
GMAT DeepSpaceProp.InitialStepSize = 60;
GMAT DeepSpaceProp.Accuracy = 9.999999999999999e-012;
GMAT DeepSpaceProp.MinStep = 0.001;
GMAT DeepSpaceProp.MaxStep = 2700;
GMAT DeepSpaceProp.MaxStepAttempts = 50;
GMAT DeepSpaceProp.StopIfAccuracyIsViolated = true;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;

% The spacecraft currently propagates straight to periapsis.
% You must insert a Target sequence here to perform the TCM
% and achieve the exact flyby parameters.
Propagate DeepSpaceProp(SolarCruiser) {SolarCruiser.Venus.Periapsis};

GMATEOF

chown ga:ga /home/ga/Documents/missions/venus_tcm_baseline.script

# 4. Launch GMAT with the baseline script
echo "Launching GMAT..."
launch_gmat "/home/ga/Documents/missions/venus_tcm_baseline.script"

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