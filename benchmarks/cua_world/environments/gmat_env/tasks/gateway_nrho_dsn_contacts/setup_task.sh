#!/bin/bash
set -euo pipefail

echo "=== Setting up gateway_nrho_dsn_contacts task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/dsn_specs.txt
rm -f /home/ga/Documents/missions/gateway_nrho*.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the DSN specifications document
cat > /home/ga/Desktop/dsn_specs.txt << 'SPECEOF'
=========================================
DEEP SPACE NETWORK (DSN) CONFIGURATION
Artemis Lunar Gateway Analysis
=========================================

STATION COORDINATES:
1. Goldstone (DSS-14)
   Central Body: Earth
   Latitude:  35.4266 deg
   Longitude: 243.1133 deg
   Altitude:  0.973 km

2. Madrid (DSS-63)
   Central Body: Earth
   Latitude:  40.4272 deg
   Longitude: 355.7505 deg
   Altitude:  0.835 km

3. Canberra (DSS-43)
   Central Body: Earth
   Latitude:  -35.4013 deg
   Longitude: 148.9813 deg
   Altitude:  0.689 km

CONSTRAINTS:
- Minimum Elevation Angle: 10.0 degrees (for all stations)
- Occulting Bodies: Earth, Moon
- Output Report Filename: /home/ga/GMAT_output/Gateway_DSN_Contacts.txt
SPECEOF

# 4. Create the baseline NRHO GMAT script
cat > /home/ga/Documents/missions/gateway_nrho_baseline.script << 'GMATEOF'
%----------------------------------------
%---------- Coordinate Systems
%----------------------------------------
Create CoordinateSystem MoonEq;
GMAT MoonEq.Origin = Luna;
GMAT MoonEq.Axes = MJ2000Eq;

%----------------------------------------
%---------- Spacecraft
%----------------------------------------
Create Spacecraft Gateway;
GMAT Gateway.DateFormat = UTCGregorian;
GMAT Gateway.Epoch = '01 Jan 2025 12:00:00.000';
GMAT Gateway.CoordinateSystem = MoonEq;
GMAT Gateway.DisplayStateType = Keplerian;
GMAT Gateway.SMA = 68000;
GMAT Gateway.ECC = 0.85;
GMAT Gateway.INC = 90;
GMAT Gateway.RAAN = 0;
GMAT Gateway.AOP = 90;
GMAT Gateway.TA = 180;
GMAT Gateway.DryMass = 20000;
GMAT Gateway.Cd = 2.2;
GMAT Gateway.Cr = 1.8;
GMAT Gateway.DragArea = 50;
GMAT Gateway.SRPArea = 100;

%----------------------------------------
%---------- ForceModels
%----------------------------------------
Create ForceModel Moon_FM;
GMAT Moon_FM.CentralBody = Luna;
GMAT Moon_FM.PrimaryBodies = {Luna};
GMAT Moon_FM.PointMasses = {Earth, Sun};
GMAT Moon_FM.Drag.AtmosphereModel = None;
GMAT Moon_FM.GravityField.Luna.Degree = 2;
GMAT Moon_FM.GravityField.Luna.Order = 2;
GMAT Moon_FM.GravityField.Luna.PotentialFile = 'LP165P.cof';
GMAT Moon_FM.SRP = Off;

%----------------------------------------
%---------- Propagators
%----------------------------------------
Create Propagator Moon_Prop;
GMAT Moon_Prop.FM = Moon_FM;
GMAT Moon_Prop.Type = PrinceDormand78;
GMAT Moon_Prop.InitialStepSize = 60;
GMAT Moon_Prop.MinStep = 0.001;
GMAT Moon_Prop.MaxStep = 2700;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;
Propagate Moon_Prop(Gateway) {Gateway.ElapsedDays = 30};
GMATEOF

chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 5. Launch GMAT
echo "Launching GMAT..."
launch_gmat "/home/ga/Documents/missions/gateway_nrho_baseline.script"

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