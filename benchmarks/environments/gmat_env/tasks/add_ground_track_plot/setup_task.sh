#!/bin/bash
echo "=== Setting up add_ground_track_plot task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Kill any existing GMAT instances
pkill -f "/opt/GMAT/bin/GMAT" 2>/dev/null || true
sleep 2

# Create a LEO propagation mission script (using real orbital parameters for ISS-like orbit)
# This uses real-world orbital elements based on a typical ISS orbit configuration
MISSION_SCRIPT="/home/ga/Documents/missions/LEO_Propagation.script"

cat > "$MISSION_SCRIPT" << 'SCRIPTEOF'
%--------------------------------------------------------------
%  LEO Spacecraft Propagation - 500 km Circular Orbit
%  Based on typical ISS orbital parameters
%  Epoch: 01 Jan 2024 12:00:00.000 UTC
%--------------------------------------------------------------

%---------- Spacecraft
Create Spacecraft LEO_Sat;
GMAT LEO_Sat.DateFormat = UTCGregorian;
GMAT LEO_Sat.Epoch = '01 Jan 2024 12:00:00.000';
GMAT LEO_Sat.CoordinateSystem = EarthMJ2000Eq;
GMAT LEO_Sat.DisplayStateType = Keplerian;
GMAT LEO_Sat.SMA = 6878.14;
GMAT LEO_Sat.ECC = 0.001;
GMAT LEO_Sat.INC = 28.5;
GMAT LEO_Sat.RAAN = 45.0;
GMAT LEO_Sat.AOP = 0.0;
GMAT LEO_Sat.TA = 0.0;

%---------- Force Model
Create ForceModel LEOProp_ForceModel;
GMAT LEOProp_ForceModel.CentralBody = Earth;
GMAT LEOProp_ForceModel.PointMasses = {Earth};
GMAT LEOProp_ForceModel.Drag = None;
GMAT LEOProp_ForceModel.SRP = Off;

%---------- Propagator
Create Propagator LEOProp;
GMAT LEOProp.FM = LEOProp_ForceModel;
GMAT LEOProp.Type = RungeKutta89;
GMAT LEOProp.InitialStepSize = 60;
GMAT LEOProp.Accuracy = 9.999999999999999e-012;
GMAT LEOProp.MinStep = 0.001;
GMAT LEOProp.MaxStep = 2700;
GMAT LEOProp.MaxStepAttempts = 50;

%---------- Subscribers (Output)
Create OrbitView DefaultOrbitView;
GMAT DefaultOrbitView.SolverIterations = Current;
GMAT DefaultOrbitView.UpperLeft = [ 0.0 0.0 ];
GMAT DefaultOrbitView.Size = [ 0.5 0.5 ];
GMAT DefaultOrbitView.RelativeZOrder = 100;
GMAT DefaultOrbitView.Maximized = false;
GMAT DefaultOrbitView.Add = {LEO_Sat, Earth};
GMAT DefaultOrbitView.CoordinateSystem = EarthMJ2000Eq;
GMAT DefaultOrbitView.DrawObject = [ true true ];
GMAT DefaultOrbitView.DataCollectFrequency = 1;
GMAT DefaultOrbitView.UpdatePlotFrequency = 50;
GMAT DefaultOrbitView.NumPointsToRedraw = 0;
GMAT DefaultOrbitView.ShowPlot = true;
GMAT DefaultOrbitView.ViewPointReference = Earth;
GMAT DefaultOrbitView.ViewPointVector = [ 30000 0 0 ];
GMAT DefaultOrbitView.ViewDirection = Earth;
GMAT DefaultOrbitView.ViewScaleFactor = 1;
GMAT DefaultOrbitView.ViewUpCoordinateSystem = EarthMJ2000Eq;
GMAT DefaultOrbitView.ViewUpAxis = Z;

%---------- Mission Sequence
BeginMissionSequence;
Propagate LEOProp(LEO_Sat) {LEO_Sat.ElapsedSecs = 86400.0};
SCRIPTEOF

chown ga:ga "$MISSION_SCRIPT"

echo "Created LEO propagation mission script at: $MISSION_SCRIPT"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch GMAT with the LEO propagation script
echo "Launching GMAT with LEO Propagation mission..."
launch_gmat "$MISSION_SCRIPT"

# Wait for GMAT window
echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 90)
if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5

    # Dismiss any startup dialogs
    dismiss_gmat_dialogs
    sleep 2

    # Maximize and focus
    focus_gmat_window
    sleep 1

    # Kill any Firefox that GMAT may have opened
    pkill -f "firefox" 2>/dev/null || true

    echo "GMAT is ready with LEO Propagation mission loaded"
else
    echo "WARNING: GMAT window did not appear, checking process..."
    ps aux | grep -i gmat | grep -v grep || true
    cat /tmp/gmat_task.log 2>/dev/null | tail -20 || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_screenshot.png
echo "Initial screenshot saved to /tmp/task_initial_screenshot.png"

echo "=== add_ground_track_plot task setup complete ==="
