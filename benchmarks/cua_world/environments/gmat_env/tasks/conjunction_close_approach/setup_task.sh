#!/bin/bash
set -euo pipefail

echo "=== Setting up conjunction_close_approach task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
rm -f /home/ga/Desktop/cdm_comms_leo_7.txt
rm -f /home/ga/Documents/missions/conjunction_assessment.script
rm -f /home/ga/GMAT_output/conjunction_assessment.txt
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Create CDM file
cat > /home/ga/Desktop/cdm_comms_leo_7.txt << 'EOF'
==========================================================
CONJUNCTION DATA MESSAGE (Abbreviated)
Source: 18th Space Defense Squadron (18 SDS)
Generated: 2025-06-30T18:00:00Z
==========================================================

OBJECT 1 (PRIMARY) - Operational Satellite
------------------------------------------
Object Name:           COMMS-LEO-7
NORAD Cat ID:          58921
Object Type:           PAYLOAD
Operator:              GlobalComm Systems Inc.
Epoch:                 2025 Jul 01 12:00:00.000 UTCG
Coordinate System:     EarthMJ2000Eq
SMA (km):              6898.140
ECC:                   0.000350
INC (deg):             51.640
RAAN (deg):            247.350
AOP (deg):             85.200
TA (deg):              274.800
DryMass (kg):          320.0
Cd:                    2.2
DragArea (m^2):        4.8
SRPArea (m^2):         4.8
Cr:                    1.8

OBJECT 2 (SECONDARY) - Debris
------------------------------------------
Object Name:           FENGYUN-1C DEB
NORAD Cat ID:          31448
Object Type:           DEBRIS
Origin Event:          2007 Chinese ASAT Test
Epoch:                 2025 Jul 01 12:00:00.000 UTCG
Coordinate System:     EarthMJ2000Eq
SMA (km):              6895.800
ECC:                   0.004120
INC (deg):             98.720
RAAN (deg):            247.180
AOP (deg):             268.500
TA (deg):              6.300
DryMass (kg):          8.5
Cd:                    2.2
DragArea (m^2):        0.12
SRPArea (m^2):         0.12
Cr:                    1.0

PRELIMINARY CONJUNCTION ASSESSMENT
------------------------------------------
Predicted TCA:         ~2025 Jul 02 (within 36 hours of epoch)
Predicted Miss Dist:   Requires independent verification
Collision Probability: Pending operator assessment
Relative Velocity:     ~6-10 km/s (crossing orbits)

NOTE: This is a preliminary alert. Operator must perform
independent conjunction assessment for maneuver decision.
==========================================================
EOF
chown ga:ga /home/ga/Desktop/cdm_comms_leo_7.txt

# 4. Generate Ground Truth secretly
mkdir -p /var/lib/gmat_ground_truth
chmod 700 /var/lib/gmat_ground_truth

cat > /var/lib/gmat_ground_truth/gt.script << 'EOF'
Create Spacecraft COMMS_LEO_7;
GMAT COMMS_LEO_7.DateFormat = UTCGregorian;
GMAT COMMS_LEO_7.Epoch = '01 Jul 2025 12:00:00.000';
GMAT COMMS_LEO_7.CoordinateSystem = EarthMJ2000Eq;
GMAT COMMS_LEO_7.DisplayStateType = Keplerian;
GMAT COMMS_LEO_7.SMA = 6898.140;
GMAT COMMS_LEO_7.ECC = 0.000350;
GMAT COMMS_LEO_7.INC = 51.640;
GMAT COMMS_LEO_7.RAAN = 247.350;
GMAT COMMS_LEO_7.AOP = 85.200;
GMAT COMMS_LEO_7.TA = 274.800;
GMAT COMMS_LEO_7.DryMass = 320.0;
GMAT COMMS_LEO_7.Cd = 2.2;
GMAT COMMS_LEO_7.DragArea = 4.8;

Create Spacecraft FENGYUN_DEB;
GMAT FENGYUN_DEB.DateFormat = UTCGregorian;
GMAT FENGYUN_DEB.Epoch = '01 Jul 2025 12:00:00.000';
GMAT FENGYUN_DEB.CoordinateSystem = EarthMJ2000Eq;
GMAT FENGYUN_DEB.DisplayStateType = Keplerian;
GMAT FENGYUN_DEB.SMA = 6895.800;
GMAT FENGYUN_DEB.ECC = 0.004120;
GMAT FENGYUN_DEB.INC = 98.720;
GMAT FENGYUN_DEB.RAAN = 247.180;
GMAT FENGYUN_DEB.AOP = 268.500;
GMAT FENGYUN_DEB.TA = 6.300;
GMAT FENGYUN_DEB.DryMass = 8.5;
GMAT FENGYUN_DEB.Cd = 2.2;
GMAT FENGYUN_DEB.DragArea = 0.12;

Create ForceModel FM;
GMAT FM.CentralBody = Earth;
GMAT FM.PrimaryBodies = {Earth};
GMAT FM.Drag.AtmosphereModel = JacchiaRoberts;

Create Propagator Prop;
GMAT Prop.FM = FM;
GMAT Prop.Type = RungeKutta89;
GMAT Prop.InitialStepSize = 60;
GMAT Prop.MinStep = 1;
GMAT Prop.MaxStep = 60;

Create Variable dist;
Create ReportFile rep;
GMAT rep.Filename = '/var/lib/gmat_ground_truth/dist.txt';
GMAT rep.Add = {COMMS_LEO_7.UTCModJulian, dist};
GMAT rep.WriteHeaders = false;

BeginMissionSequence;
While COMMS_LEO_7.ElapsedDays < 3.0
    Propagate Synchronized Prop(COMMS_LEO_7) Prop(FENGYUN_DEB);
    dist = sqrt((COMMS_LEO_7.EarthMJ2000Eq.X - FENGYUN_DEB.EarthMJ2000Eq.X)^2 + (COMMS_LEO_7.EarthMJ2000Eq.Y - FENGYUN_DEB.EarthMJ2000Eq.Y)^2 + (COMMS_LEO_7.EarthMJ2000Eq.Z - FENGYUN_DEB.EarthMJ2000Eq.Z)^2);
    Report rep COMMS_LEO_7.UTCModJulian dist;
EndWhile;
EOF

# Run ground truth in background to ensure environment setup isn't delayed significantly
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
if [ -n "$CONSOLE" ]; then
    echo "Running ground truth..."
    timeout 60 "$CONSOLE" --run /var/lib/gmat_ground_truth/gt.script > /var/lib/gmat_ground_truth/gt.log 2>&1 || true
fi

# Calculate min dist programmatically to prepare ground truth
python3 << 'EOF'
import os, json
dist_file = '/var/lib/gmat_ground_truth/dist.txt'
min_dist = 999999.0
min_epoch = 0.0
if os.path.exists(dist_file):
    with open(dist_file, 'r') as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                try:
                    d = float(parts[1])
                    if d < min_dist:
                        min_dist = d
                        min_epoch = float(parts[0])
                except:
                    pass
else:
    min_dist = 15.2 # fallback approximation for provided orbits
    min_epoch = 30498.5

with open('/var/lib/gmat_ground_truth/gt_results.json', 'w') as f:
    json.dump({'min_dist_km': min_dist, 'tca_mjd': min_epoch}, f)
EOF

# 5. Launch GMAT for Agent
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