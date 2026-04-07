#!/bin/bash
set -euo pipefail

echo "=== Setting up broken_leo_mission_diagnosis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Documents/missions/leo_comms_mission.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Write the broken GMAT script with 4 injected physical errors:
#    Error 1: SMA = 7300.0 km  (should be ~6921.14 km for 550 km altitude)
#    Error 2: ECC = 0.05       (should be ~0.001 for near-circular comms orbit)
#    Error 3: INC = 55.0 deg   (should be ~97.73 deg for sun-synchronous at 550 km)
#    Error 4: DragArea = 0.0001 m^2  (should be ~10-30 m^2 for a 520 kg comms sat)
cat > /home/ga/Documents/missions/leo_comms_mission.script << 'GMATEOF'
%----------------------------------------
%---------- Spacecraft
%----------------------------------------
% LeoComm-1: 550 km Sun-Synchronous Dawn-Dusk Communications Satellite
% Mission: Broadband Internet coverage, 520 kg spacecraft
% NOTE: This script was prepared by a junior analyst and contains errors.
%       Please diagnose and correct all physical inconsistencies.

Create Spacecraft LeoComm;
GMAT LeoComm.DateFormat = UTCGregorian;
GMAT LeoComm.Epoch = '01 Jan 2025 06:00:00.000';
GMAT LeoComm.CoordinateSystem = EarthMJ2000Eq;
GMAT LeoComm.DisplayStateType = Keplerian;
GMAT LeoComm.SMA = 7300.0;
GMAT LeoComm.ECC = 0.05;
GMAT LeoComm.INC = 55.0;
GMAT LeoComm.RAAN = 90.0;
GMAT LeoComm.AOP = 0.0;
GMAT LeoComm.TA = 0.0;
GMAT LeoComm.DryMass = 520;
GMAT LeoComm.Cd = 2.2;
GMAT LeoComm.Cr = 1.8;
GMAT LeoComm.DragArea = 0.0001;
GMAT LeoComm.SRPArea = 10.0;
GMAT LeoComm.NAIFId = -10001001;
GMAT LeoComm.NAIFIdReferenceFrame = -9001001;
GMAT LeoComm.OrbitColor = Red;
GMAT LeoComm.TargetColor = Teal;
GMAT LeoComm.OrbitErrorCovariance = [ 1e+070 0 0 0 0 0 ; 0 1e+070 0 0 0 0 ; 0 0 1e+070 0 0 0 ; 0 0 0 1e+070 0 0 ; 0 0 0 0 1e+070 0 ; 0 0 0 0 0 1e+070 ];
GMAT LeoComm.CdSigma = 1e+070;
GMAT LeoComm.CrSigma = 1e+070;
GMAT LeoComm.Id = 'SatId';
GMAT LeoComm.Attitude = CoordinateSystemFixed;
GMAT LeoComm.SPADSRPScaleFactor = 1;
GMAT LeoComm.ModelFile = 'aura.3ds';
GMAT LeoComm.ModelOffsetX = 0;
GMAT LeoComm.ModelOffsetY = 0;
GMAT LeoComm.ModelOffsetZ = 0;
GMAT LeoComm.ModelRotationX = 0;
GMAT LeoComm.ModelRotationY = 0;
GMAT LeoComm.ModelRotationZ = 0;
GMAT LeoComm.ModelScale = 1;
GMAT LeoComm.AttitudeDisplayStateType = 'Quaternion';
GMAT LeoComm.AttitudeRateDisplayStateType = 'AngularVelocity';
GMAT LeoComm.AttitudeCoordinateSystem = EarthMJ2000Eq;
GMAT LeoComm.EulerAngleSequence = '321';

%----------------------------------------
%---------- ForceModels
%----------------------------------------

Create ForceModel LEO_ForceModel;
GMAT LEO_ForceModel.CentralBody = Earth;
GMAT LEO_ForceModel.PrimaryBodies = {Earth};
GMAT LEO_ForceModel.PointMasses = {Luna, Sun};
GMAT LEO_ForceModel.Drag.AtmosphereModel = JacchiaRoberts;
GMAT LEO_ForceModel.Drag.HistoricWeatherSource = 'CSSISpaceWeatherFile';
GMAT LEO_ForceModel.Drag.PredictedWeatherSource = 'ConstantFluxAndGeoMag';
GMAT LEO_ForceModel.Drag.CSSISpaceWeatherFile = 'SpaceWeather-All-v1.2.txt';
GMAT LEO_ForceModel.Drag.SchattenFile = 'SchattenPredict.txt';
GMAT LEO_ForceModel.Drag.F107 = 150;
GMAT LEO_ForceModel.Drag.F107A = 150;
GMAT LEO_ForceModel.Drag.MagneticIndex = 3;
GMAT LEO_ForceModel.Drag.SchattenErrorModel = 'Nominal';
GMAT LEO_ForceModel.Drag.SchattenTimingModel = 'NominalCycle';
GMAT LEO_ForceModel.Drag.DragModel = 'Spherical';
GMAT LEO_ForceModel.GravityField.Earth.Degree = 8;
GMAT LEO_ForceModel.GravityField.Earth.Order = 8;
GMAT LEO_ForceModel.GravityField.Earth.StmLimit = 100;
GMAT LEO_ForceModel.GravityField.Earth.GravityFile = 'JGM2.cof';
GMAT LEO_ForceModel.GravityField.Earth.TideModel = 'None';
GMAT LEO_ForceModel.SRP = Off;
GMAT LEO_ForceModel.RelativisticCorrection = Off;
GMAT LEO_ForceModel.ErrorControl = RSSStep;

%----------------------------------------
%---------- Propagators
%----------------------------------------

Create Propagator LEO_Prop;
GMAT LEO_Prop.FM = LEO_ForceModel;
GMAT LEO_Prop.Type = RungeKutta89;
GMAT LEO_Prop.InitialStepSize = 60;
GMAT LEO_Prop.Accuracy = 9.999999999999999e-012;
GMAT LEO_Prop.MinStep = 0.001;
GMAT LEO_Prop.MaxStep = 2700;
GMAT LEO_Prop.MaxStepAttempts = 50;
GMAT LEO_Prop.StopIfAccuracyIsViolated = true;

%----------------------------------------
%---------- Subscribers
%----------------------------------------

Create ReportFile LeoCommReport;
GMAT LeoCommReport.SolverIterations = Current;
GMAT LeoCommReport.UpperLeft = [ 0.02 0.02 ];
GMAT LeoCommReport.Size = [ 0.59 0.79 ];
GMAT LeoCommReport.RelativeZOrder = 14;
GMAT LeoCommReport.Maximized = false;
GMAT LeoCommReport.Filename = '/home/ga/GMAT_output/leo_comms_report.txt';
GMAT LeoCommReport.Precision = 16;
GMAT LeoCommReport.Add = {LeoComm.UTCGregorian, LeoComm.Earth.Altitude, LeoComm.EarthMJ2000Eq.RAAN, LeoComm.Earth.SMA, LeoComm.ECC};
GMAT LeoCommReport.WriteHeaders = true;
GMAT LeoCommReport.LeftJustify = On;
GMAT LeoCommReport.ZeroFill = Off;
GMAT LeoCommReport.FixedWidth = true;
GMAT LeoCommReport.Delimiter = ' ';
GMAT LeoCommReport.ColumnWidth = 23;
GMAT LeoCommReport.WriteReport = true;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;
Propagate LEO_Prop(LeoComm) {LeoComm.ElapsedDays = 7.0};
GMATEOF

chown ga:ga /home/ga/Documents/missions/leo_comms_mission.script

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

echo "=== Task Setup Complete: broken GMAT script ready at /home/ga/Documents/missions/leo_comms_mission.script ==="
