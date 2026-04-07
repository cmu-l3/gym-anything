#!/bin/bash
set -euo pipefail

echo "=== Setting up planetary_defense_deflection task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output/*
rm -f /home/ga/Documents/missions/pdc_deflection_base.script
rm -f /home/ga/Documents/missions/asteroid_deflection.script
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the base GMAT script
# This script sets up a synthetic Earth-impacting asteroid.
# The agent must fill in the Target loop to deflect it to exactly 20,000 km RMAG.
cat > /home/ga/Documents/missions/pdc_deflection_base.script << 'GMATEOF'
%----------------------------------------
%---------- Spacecraft
%----------------------------------------

Create Spacecraft Ast2028;
GMAT Ast2028.DateFormat = UTCGregorian;
GMAT Ast2028.Epoch = '01 Jan 2025 00:00:00.000';
GMAT Ast2028.CoordinateSystem = SunICRF;
GMAT Ast2028.DisplayStateType = Cartesian;
GMAT Ast2028.X = 145000000.0;
GMAT Ast2028.Y = 25000000.0;
GMAT Ast2028.Z = 0.0;
GMAT Ast2028.VX = -5.0;
GMAT Ast2028.VY = 28.0;
GMAT Ast2028.VZ = 1.2;
GMAT Ast2028.DryMass = 1000000;
GMAT Ast2028.Cd = 2.2;
GMAT Ast2028.Cr = 1.0;
GMAT Ast2028.DragArea = 1000;
GMAT Ast2028.SRPArea = 1000;

%----------------------------------------
%---------- ForceModels
%----------------------------------------

Create ForceModel DeepSpace_FM;
GMAT DeepSpace_FM.CentralBody = Sun;
GMAT DeepSpace_FM.PointMasses = {Earth, Jupiter, Luna, Sun};
GMAT DeepSpace_FM.Drag = None;
GMAT DeepSpace_FM.SRP = Off;
GMAT DeepSpace_FM.RelativisticCorrection = Off;
GMAT DeepSpace_FM.ErrorControl = RSSStep;

%----------------------------------------
%---------- Propagators
%----------------------------------------

Create Propagator DeepSpaceProp;
GMAT DeepSpaceProp.FM = DeepSpace_FM;
GMAT DeepSpaceProp.Type = PrinceDormand78;
GMAT DeepSpaceProp.InitialStepSize = 3600;
GMAT DeepSpaceProp.Accuracy = 1e-11;
GMAT DeepSpaceProp.MinStep = 0.001;
GMAT DeepSpaceProp.MaxStep = 864000;

%----------------------------------------
%---------- Coordinate Systems
%----------------------------------------

Create CoordinateSystem SunICRF;
GMAT SunICRF.Origin = Sun;
GMAT SunICRF.Axes = ICRF;

%----------------------------------------
%---------- Burns
%----------------------------------------

Create ImpulsiveBurn DeflectionBurn;
GMAT DeflectionBurn.CoordinateSystem = Local;
GMAT DeflectionBurn.Origin = Ast2028;
GMAT DeflectionBurn.Axes = VNB;
GMAT DeflectionBurn.Element1 = 0;
GMAT DeflectionBurn.Element2 = 0;
GMAT DeflectionBurn.Element3 = 0;

%----------------------------------------
%---------- Solvers
%----------------------------------------

Create DifferentialCorrector DC1;
GMAT DC1.ShowProgress = true;
GMAT DC1.ReportStyle = Normal;
GMAT DC1.ReportFile = '/tmp/DC1_report.txt';
GMAT DC1.MaximumIterations = 50;
GMAT DC1.DerivativeMethod = ForwardDifference;
GMAT DC1.Algorithm = NewtonRaphson;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------

BeginMissionSequence;

% Propagate 10 days before applying the deflection maneuver
Propagate DeepSpaceProp(Ast2028) {Ast2028.ElapsedDays = 10.0};

% --- AGENT TASK STARTS HERE ---
% You must build a Target sequence here using DC1:
% 1. Vary DeflectionBurn.Element1 (initial guess -1e-5, perturb 1e-6, MaxStep 1e-4)
% 2. Apply DeflectionBurn to Ast2028
% 3. Propagate Ast2028 to Ast2028.Earth.Periapsis (closest approach)
% 4. Achieve Ast2028.Earth.RMAG = 20000.0 (exact miss distance)

Target DC1;
    % Add Vary, Maneuver, Propagate, and Achieve commands here
    
EndTarget;

% --- AGENT TASK ENDS HERE ---
GMATEOF

chown ga:ga /home/ga/Documents/missions/pdc_deflection_base.script

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

echo "=== Task Setup Complete: Base script ready at ~/Documents/missions/pdc_deflection_base.script ==="