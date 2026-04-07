#!/bin/bash
set -euo pipefail

echo "=== Setting up debris_avoidance_maneuver_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Documents/missions/dam_analysis.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the initial GMAT script
# This script propagates two objects to a predicted TCA exactly 24h from epoch
cat > /home/ga/Documents/missions/dam_analysis.script << 'GMATEOF'
%----------------------------------------
%---------- Spacecraft
%----------------------------------------
Create Spacecraft EarthObs;
GMAT EarthObs.DateFormat = UTCGregorian;
GMAT EarthObs.Epoch = '01 Jan 2026 12:00:00.000';
GMAT EarthObs.CoordinateSystem = EarthMJ2000Eq;
GMAT EarthObs.DisplayStateType = Keplerian;
GMAT EarthObs.SMA = 7000.0;
GMAT EarthObs.ECC = 0.001;
GMAT EarthObs.INC = 98.2;
GMAT EarthObs.RAAN = 45.0;
GMAT EarthObs.AOP = 0.0;
GMAT EarthObs.TA = 0.0;
GMAT EarthObs.DryMass = 850;
GMAT EarthObs.Cd = 2.2;
GMAT EarthObs.DragArea = 2.5;

Create Spacecraft CosmosDebris;
GMAT CosmosDebris.DateFormat = UTCGregorian;
GMAT CosmosDebris.Epoch = '01 Jan 2026 12:00:00.000';
GMAT CosmosDebris.CoordinateSystem = EarthMJ2000Eq;
GMAT CosmosDebris.DisplayStateType = Keplerian;
GMAT CosmosDebris.SMA = 7001.0;
GMAT CosmosDebris.ECC = 0.002;
GMAT CosmosDebris.INC = 98.3;
GMAT CosmosDebris.RAAN = 45.1;
GMAT CosmosDebris.AOP = 0.0;
GMAT CosmosDebris.TA = 0.5;
GMAT CosmosDebris.DryMass = 1200;
GMAT CosmosDebris.Cd = 2.2;
GMAT CosmosDebris.DragArea = 10.0;

%----------------------------------------
%---------- ForceModels & Propagators
%----------------------------------------
Create ForceModel DefaultProp_ForceModel;
GMAT DefaultProp_ForceModel.CentralBody = Earth;
GMAT DefaultProp_ForceModel.PrimaryBodies = {Earth};
GMAT DefaultProp_ForceModel.Drag.AtmosphereModel = JacchiaRoberts;
GMAT DefaultProp_ForceModel.Drag.F107 = 150;
GMAT DefaultProp_ForceModel.Drag.F107A = 150;
GMAT DefaultProp_ForceModel.Drag.MagneticIndex = 3;
GMAT DefaultProp_ForceModel.GravityField.Earth.Degree = 4;
GMAT DefaultProp_ForceModel.GravityField.Earth.Order = 4;

Create Propagator DefaultProp;
GMAT DefaultProp.FM = DefaultProp_ForceModel;

%----------------------------------------
%---------- Variables
%----------------------------------------
Create Variable MissDistance_km;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;

% Propagate to expected Time of Closest Approach (TCA) at 24 hours
Propagate DefaultProp(EarthObs, CosmosDebris) {EarthObs.ElapsedSecs = 86400.0};

% Calculate Miss Distance at TCA
MissDistance_km = sqrt((EarthObs.X - CosmosDebris.X)^2 + (EarthObs.Y - CosmosDebris.Y)^2 + (EarthObs.Z - CosmosDebris.Z)^2);

% NOTE FOR ANALYST: 
% The miss distance at this TCA is highly dangerous. 
% You must split the propagation, insert a Debris Avoidance Maneuver (DAM) 
% exactly at EarthObs.ElapsedSecs = 43200, and ensure final MissDistance_km >= 2.0.
GMATEOF

chown ga:ga /home/ga/Documents/missions/dam_analysis.script

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

echo "=== Task Setup Complete: dam_analysis.script ready ==="