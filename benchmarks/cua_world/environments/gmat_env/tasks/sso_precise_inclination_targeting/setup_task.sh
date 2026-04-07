#!/bin/bash
set -euo pipefail

echo "=== Setting up sso_precise_inclination_targeting task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/Documents/missions
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the baseline script
cat > /home/ga/Documents/missions/sso_baseline.script << 'GMATEOF'
%----------------------------------------
%---------- Spacecraft
%----------------------------------------
Create Spacecraft Sat;
GMAT Sat.DateFormat = UTCGregorian;
GMAT Sat.Epoch = '01 Jan 2025 12:00:00.000';
GMAT Sat.CoordinateSystem = EarthMJ2000Eq;
GMAT Sat.DisplayStateType = Keplerian;
GMAT Sat.SMA = 6971.14;
GMAT Sat.ECC = 0.001;
GMAT Sat.INC = 97.787;  % Initial analytical guess (J2-only)
GMAT Sat.RAAN = 0.0;
GMAT Sat.AOP = 0.0;
GMAT Sat.TA = 0.0;
GMAT Sat.DryMass = 850;
GMAT Sat.Cd = 2.2;
GMAT Sat.Cr = 1.8;
GMAT Sat.DragArea = 15;
GMAT Sat.SRPArea = 15;

%----------------------------------------
%---------- ForceModels
%----------------------------------------
Create ForceModel DefaultProp_ForceModel;
GMAT DefaultProp_ForceModel.CentralBody = Earth;
GMAT DefaultProp_ForceModel.PrimaryBodies = {Earth};
GMAT DefaultProp_ForceModel.PointMasses = {Luna, Sun};
GMAT DefaultProp_ForceModel.GravityField.Earth.Degree = 10;
GMAT DefaultProp_ForceModel.GravityField.Earth.Order = 10;
GMAT DefaultProp_ForceModel.GravityField.Earth.PotentialFile = 'JGM2.cof';

%----------------------------------------
%---------- Propagators
%----------------------------------------
Create Propagator DefaultProp;
GMAT DefaultProp.FM = DefaultProp_ForceModel;
GMAT DefaultProp.Type = RungeKutta89;
GMAT DefaultProp.InitialStepSize = 60;
GMAT DefaultProp.MinStep = 0.001;
GMAT DefaultProp.MaxStep = 2700;

%----------------------------------------
%---------- Subscribers
%----------------------------------------
Create ReportFile OrbitReport;
GMAT OrbitReport.Filename = '/home/ga/GMAT_output/OrbitData.txt';
GMAT OrbitReport.Add = {Sat.UTCGregorian, Sat.EarthMJ2000Eq.INC, Sat.EarthMJ2000Eq.RAAN};
GMAT OrbitReport.WriteHeaders = true;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;
Propagate DefaultProp(Sat) {Sat.ElapsedDays = 10.0};
GMATEOF

chown ga:ga /home/ga/Documents/missions/sso_baseline.script

# 4. Launch GMAT GUI
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