#!/bin/bash
set -euo pipefail

echo "=== Setting up geo_defunct_drift_hazard_prediction task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -f /home/ga/Documents/missions/defunct_geo_hazard.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Create the starter script (Intentionally flawed Point Mass model)
cat > /home/ga/Documents/missions/defunct_geo_hazard.script << 'GMATEOF'
% Geostationary Defunct Satellite Drift Analysis
Create Spacecraft DefunctSat;
GMAT DefunctSat.DateFormat = UTCGregorian;
GMAT DefunctSat.Epoch = '01 Jan 2026 12:00:00.000';
GMAT DefunctSat.CoordinateSystem = EarthMJ2000Eq;
GMAT DefunctSat.DisplayStateType = Keplerian;
GMAT DefunctSat.SMA = 42164.169;
GMAT DefunctSat.ECC = 0.0001;
GMAT DefunctSat.INC = 0.05;
GMAT DefunctSat.RAAN = 0.0;
GMAT DefunctSat.AOP = 0.0;
GMAT DefunctSat.TA = 260.0; % Placed approximately at 15.0W longitude

Create ForceModel PointMassFM;
GMAT PointMassFM.CentralBody = Earth;
GMAT PointMassFM.PrimaryBodies = {Earth};
GMAT PointMassFM.PointMasses = {Sun, Luna};
% ERROR: Point mass gravity will not model triaxial longitude drift!
GMAT PointMassFM.GravityField.Earth.Degree = 0;
GMAT PointMassFM.GravityField.Earth.Order = 0;
GMAT PointMassFM.GravityField.Earth.PotentialFile = 'JGM2.cof';

Create Propagator GEOProp;
GMAT GEOProp.FM = PointMassFM;
GMAT GEOProp.Type = RungeKutta89;
GMAT GEOProp.InitialStepSize = 3600;
GMAT GEOProp.Accuracy = 9.999999999999999e-012;
GMAT GEOProp.MinStep = 0.001;
GMAT GEOProp.MaxStep = 27000;

Create ReportFile Report1;
GMAT Report1.Filename = '/home/ga/GMAT_output/DefaultReport.txt';
GMAT Report1.Add = {DefunctSat.UTCGregorian, DefunctSat.Earth.Longitude};

Create Propagate Prop1;
GMAT Prop1.Propagator = GEOProp;
GMAT Prop1.StopCondition = {DefunctSat.ElapsedDays = 730};
GMATEOF

chown ga:ga /home/ga/Documents/missions/defunct_geo_hazard.script

# 4. Generate Ground Truth (Same as starter, but with Degree=8, Order=8)
cat > /tmp/gt_hazard.script << 'GTEOF'
Create Spacecraft DefunctSat;
GMAT DefunctSat.DateFormat = UTCGregorian;
GMAT DefunctSat.Epoch = '01 Jan 2026 12:00:00.000';
GMAT DefunctSat.CoordinateSystem = EarthMJ2000Eq;
GMAT DefunctSat.DisplayStateType = Keplerian;
GMAT DefunctSat.SMA = 42164.169;
GMAT DefunctSat.ECC = 0.0001;
GMAT DefunctSat.INC = 0.05;
GMAT DefunctSat.RAAN = 0.0;
GMAT DefunctSat.AOP = 0.0;
GMAT DefunctSat.TA = 260.0;

Create ForceModel JGM3_8x8;
GMAT JGM3_8x8.CentralBody = Earth;
GMAT JGM3_8x8.PrimaryBodies = {Earth};
GMAT JGM3_8x8.PointMasses = {Sun, Luna};
GMAT JGM3_8x8.GravityField.Earth.Degree = 8;
GMAT JGM3_8x8.GravityField.Earth.Order = 8;
GMAT JGM3_8x8.GravityField.Earth.PotentialFile = 'JGM2.cof';

Create Propagator GEOProp;
GMAT GEOProp.FM = JGM3_8x8;
GMAT GEOProp.Type = RungeKutta89;
GMAT GEOProp.InitialStepSize = 86400;
GMAT GEOProp.Accuracy = 9.999999999999999e-012;
GMAT GEOProp.MinStep = 0.001;
GMAT GEOProp.MaxStep = 86400;

Create ReportFile Report1;
GMAT Report1.Filename = '/tmp/gt_report.txt';
GMAT Report1.Add = {DefunctSat.UTCGregorian, DefunctSat.Earth.Longitude};

Create Propagate Prop1;
GMAT Prop1.Propagator = GEOProp;
GMAT Prop1.StopCondition = {DefunctSat.ElapsedDays = 730};
GTEOF

echo "Calculating analytical ground truth..."
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
if [ -n "$CONSOLE" ]; then
    timeout 60 "$CONSOLE" --run /tmp/gt_hazard.script > /dev/null 2>&1 || true
    
    # Extract the exact crossing date using python
    cat > /tmp/extract_gt.py << 'PYEOF'
import sys
try:
    with open('/tmp/gt_report.txt', 'r') as f:
        lines = f.readlines()
    for line in lines:
        parts = line.split()
        if len(parts) >= 5:
            try:
                lon = float(parts[-1])
                # Check for crossing -35.0 or 325.0
                if lon <= -35.0 or (180 < lon <= 325.0):
                    print(f"{parts[0]} {parts[1]} {parts[2]}")
                    sys.exit(0)
            except ValueError:
                pass
    print("NOT_FOUND")
except Exception as e:
    print("NOT_FOUND")
PYEOF
    python3 /tmp/extract_gt.py > /tmp/ground_truth_date.txt
else:
    echo "NOT_FOUND" > /tmp/ground_truth_date.txt
fi

chown -R ga:ga /home/ga/GMAT_output

# 5. Launch GMAT
echo "Launching GMAT..."
launch_gmat "/home/ga/Documents/missions/defunct_geo_hazard.script"

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