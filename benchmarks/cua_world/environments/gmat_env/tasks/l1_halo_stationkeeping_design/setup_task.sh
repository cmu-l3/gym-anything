#!/bin/bash
set -euo pipefail

echo "=== Setting up l1_halo_stationkeeping_design task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the baseline GMAT script
cat > /home/ga/Documents/missions/dscovr_baseline.script << 'GMATEOF'
%----------------------------------------
%---------- Libration Points
%----------------------------------------
Create LibrationPoint SunEarthL1;
GMAT SunEarthL1.OrbitColor = Green;
GMAT SunEarthL1.TargetColor = LightGray;
GMAT SunEarthL1.Primary = Sun;
GMAT SunEarthL1.Secondary = Earth;
GMAT SunEarthL1.Point = L1;

%----------------------------------------
%---------- Coordinate Systems
%----------------------------------------
Create CoordinateSystem SunEarthRot;
GMAT SunEarthRot.Origin = SunEarthL1;
GMAT SunEarthRot.Axes = ObjectReferenced;
GMAT SunEarthRot.XAxis = R;
GMAT SunEarthRot.ZAxis = N;
GMAT SunEarthRot.Primary = Sun;
GMAT SunEarthRot.Secondary = Earth;

%----------------------------------------
%---------- Spacecraft
%----------------------------------------
Create Spacecraft DSCOVR;
GMAT DSCOVR.DateFormat = UTCGregorian;
GMAT DSCOVR.Epoch = '01 Jan 2026 12:00:00.000';
GMAT DSCOVR.CoordinateSystem = SunEarthRot;
GMAT DSCOVR.DisplayStateType = Cartesian;
GMAT DSCOVR.X = 0;
GMAT DSCOVR.Y = 0;
GMAT DSCOVR.Z = 120000;
GMAT DSCOVR.VX = 0.005;
GMAT DSCOVR.VY = -0.150;
GMAT DSCOVR.VZ = 0;
GMAT DSCOVR.DryMass = 570;
GMAT DSCOVR.Cd = 2.2;
GMAT DSCOVR.Cr = 1.4;
GMAT DSCOVR.DragArea = 10;
GMAT DSCOVR.SRPArea = 10;

%----------------------------------------
%---------- ForceModels
%----------------------------------------
Create ForceModel L1_FM;
GMAT L1_FM.CentralBody = Earth;
GMAT L1_FM.PointMasses = {Earth, Jupiter, Luna, Sun, Venus};
GMAT L1_FM.Drag = None;
GMAT L1_FM.SRP = Off;
GMAT L1_FM.RelativisticCorrection = Off;
GMAT L1_FM.ErrorControl = RSSStep;

%----------------------------------------
%---------- Propagators
%----------------------------------------
Create Propagator L1Prop;
GMAT L1Prop.FM = L1_FM;
GMAT L1Prop.Type = PrinceDormand78;
GMAT L1Prop.InitialStepSize = 600;
GMAT L1Prop.Accuracy = 9.999999999999999e-012;
GMAT L1Prop.MinStep = 0;
GMAT L1Prop.MaxStep = 86400;

%----------------------------------------
%---------- Burns
%----------------------------------------
Create ImpulsiveBurn SKM_Burn;
GMAT SKM_Burn.CoordinateSystem = Local; % AGENT MUST FIX THIS
GMAT SKM_Burn.Origin = Earth;
GMAT SKM_Burn.Axes = VNB;
GMAT SKM_Burn.Element1 = 0;
GMAT SKM_Burn.Element2 = 0;
GMAT SKM_Burn.Element3 = 0;

%----------------------------------------
%---------- Solvers
%----------------------------------------
Create DifferentialCorrector DC1;
GMAT DC1.ShowProgress = true;
GMAT DC1.ReportStyle = Normal;
GMAT DC1.ReportFile = 'DifferentialCorrectorDC1.data';
GMAT DC1.MaximumIterations = 25;
GMAT DC1.DerivativeMethod = ForwardDifference;
GMAT DC1.Algorithm = NewtonRaphson;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;

% AGENT MUST IMPLEMENT DC TARGETING LOGIC HERE

GMATEOF

# Set permissions
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 4. Launch GMAT
echo "Launching GMAT..."
launch_gmat "/home/ga/Documents/missions/dscovr_baseline.script"

echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 60)

if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    
    # Let UI settle
    sleep 2
    
    # Take initial screenshot for evidence
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="