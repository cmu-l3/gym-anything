#!/bin/bash
set -euo pipefail

echo "=== Setting up ops_log_trajectory_reconstruction task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/ops_log_satnav42.txt
rm -f /home/ga/Documents/missions/trajectory_reconstruction.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the Operations Log
cat > /home/ga/Desktop/ops_log_satnav42.txt << 'LOGEOF'
=============================================================
SATNAV-42 OPERATIONS LOG — 2025-06-09 to 2025-06-16
Flight Dynamics Team — Weekly Maneuver Summary
=============================================================

SPACECRAFT: SATNAV-42
CONSTELLATION: NavStar-G3 (MEO navigation augmentation)

INITIAL STATE (Post-tracking OD solution, 09 Jun 2025 00:00:00.000 UTCG):
  Coordinate System: EarthMJ2000Eq
  SMA   = 7178.14 km
  ECC   = 0.00125
  INC   = 52.0 deg
  RAAN  = 78.5 deg
  AOP   = 90.0 deg
  TA    = 0.0 deg
  DryMass   = 680 kg
  Cd        = 2.2
  DragArea  = 4.5 m^2
  Cr        = 1.4
  SRPArea   = 8.0 m^2

FORCE MODEL NOTES:
  Gravity: JGM-3 20x20
  Atmosphere: JacchiaRoberts (Use GMAT default settings)
  SRP: On
  Point masses: Luna, Sun

---------- MANEUVER 1: Drag Makeup ----------
Execution Epoch: 09 Jun 2025 14:30:00.000 UTCG
Frame: VNB (Velocity-Normal-Binormal)
Delta-V: [0.045, 0.0, 0.0] km/s
Purpose: Routine along-track drag compensation

---------- MANEUVER 2: Collision Avoidance ----------
Execution Epoch: 11 Jun 2025 22:15:00.000 UTCG
Frame: VNB (Velocity-Normal-Binormal)
Delta-V: [0.012, 0.008, -0.003] km/s
Purpose: CA maneuver — conjunction with debris obj 45291

---------- MANEUVER 3: Drag Makeup / Orbit Correction ----------
Execution Epoch: 14 Jun 2025 06:45:00.000 UTCG
Frame: VNB (Velocity-Normal-Binormal)
Delta-V: [0.038, -0.005, 0.0] km/s
Purpose: Post-CA orbit restoration + drag makeup

---------- END OF MANEUVER LOG ----------

FINAL EPOCH FOR STATE REPORT: 16 Jun 2025 00:00:00.000 UTCG

ANALYST INSTRUCTIONS:
  Reconstruct full trajectory from initial state through all 3 burns.
  Propagate to final epoch (16 Jun 2025 00:00:00.000 UTCG).
  Report final Keplerian state (SMA, ECC, INC, RAAN, AOP, TA) in EarthMJ2000Eq frame.
  Save report to ~/GMAT_output/reconstructed_state.txt
=============================================================
LOGEOF

chown ga:ga /home/ga/Desktop/ops_log_satnav42.txt

# 4. Generate Ground Truth via GmatConsole
echo "Generating exact ground truth state..."
cat > /tmp/gt_mission.script << 'GTEOF'
Create Spacecraft SATNAV;
GMAT SATNAV.DateFormat = UTCGregorian;
GMAT SATNAV.Epoch = '09 Jun 2025 00:00:00.000';
GMAT SATNAV.CoordinateSystem = EarthMJ2000Eq;
GMAT SATNAV.DisplayStateType = Keplerian;
GMAT SATNAV.SMA = 7178.14;
GMAT SATNAV.ECC = 0.00125;
GMAT SATNAV.INC = 52.0;
GMAT SATNAV.RAAN = 78.5;
GMAT SATNAV.AOP = 90.0;
GMAT SATNAV.TA = 0.0;
GMAT SATNAV.DryMass = 680;
GMAT SATNAV.Cd = 2.2;
GMAT SATNAV.Cr = 1.4;
GMAT SATNAV.DragArea = 4.5;
GMAT SATNAV.SRPArea = 8.0;

Create ForceModel FM;
GMAT FM.CentralBody = Earth;
GMAT FM.PrimaryBodies = {Earth};
GMAT FM.PointMasses = {Luna, Sun};
GMAT FM.GravityField.Earth.Degree = 20;
GMAT FM.GravityField.Earth.Order = 20;
GMAT FM.GravityField.Earth.GravityFile = 'JGM3.cof';
GMAT FM.Drag.AtmosphereModel = JacchiaRoberts;
GMAT FM.SRP = On;

Create Propagator Prop;
GMAT Prop.FM = FM;
GMAT Prop.Type = RungeKutta89;

Create ImpulsiveBurn Burn1;
GMAT Burn1.CoordinateSystem = Local;
GMAT Burn1.Origin = Earth;
GMAT Burn1.Axes = VNB;
GMAT Burn1.Element1 = 0.045;

Create ImpulsiveBurn Burn2;
GMAT Burn2.CoordinateSystem = Local;
GMAT Burn2.Origin = Earth;
GMAT Burn2.Axes = VNB;
GMAT Burn2.Element1 = 0.012;
GMAT Burn2.Element2 = 0.008;
GMAT Burn2.Element3 = -0.003;

Create ImpulsiveBurn Burn3;
GMAT Burn3.CoordinateSystem = Local;
GMAT Burn3.Origin = Earth;
GMAT Burn3.Axes = VNB;
GMAT Burn3.Element1 = 0.038;
GMAT Burn3.Element2 = -0.005;

Create ReportFile RF;
GMAT RF.Filename = '/tmp/gt_report.txt';
GMAT RF.Add = {SATNAV.EarthMJ2000Eq.SMA, SATNAV.EarthMJ2000Eq.ECC, SATNAV.EarthMJ2000Eq.INC, SATNAV.EarthMJ2000Eq.RAAN, SATNAV.EarthMJ2000Eq.AOP, SATNAV.EarthMJ2000Eq.TA};
GMAT RF.WriteHeaders = false;

BeginMissionSequence;
Propagate Prop(SATNAV) {SATNAV.UTCGregorian = '09 Jun 2025 14:30:00.000'};
Maneuver Burn1(SATNAV);
Propagate Prop(SATNAV) {SATNAV.UTCGregorian = '11 Jun 2025 22:15:00.000'};
Maneuver Burn2(SATNAV);
Propagate Prop(SATNAV) {SATNAV.UTCGregorian = '14 Jun 2025 06:45:00.000'};
Maneuver Burn3(SATNAV);
Propagate Prop(SATNAV) {SATNAV.UTCGregorian = '16 Jun 2025 00:00:00.000'};
Report RF SATNAV.EarthMJ2000Eq.SMA SATNAV.EarthMJ2000Eq.ECC SATNAV.EarthMJ2000Eq.INC SATNAV.EarthMJ2000Eq.RAAN SATNAV.EarthMJ2000Eq.AOP SATNAV.EarthMJ2000Eq.TA;
GTEOF

CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
if [ -n "$CONSOLE" ]; then
    "$CONSOLE" --run /tmp/gt_mission.script > /dev/null 2>&1 || true
    
    # Extract values
    if [ -f /tmp/gt_report.txt ]; then
        VALS=$(tail -1 /tmp/gt_report.txt)
        SMA=$(echo "$VALS" | awk '{print $1}')
        ECC=$(echo "$VALS" | awk '{print $2}')
        INC=$(echo "$VALS" | awk '{print $3}')
        RAAN=$(echo "$VALS" | awk '{print $4}')
        
        cat > /tmp/gt_state.json << JSONEOF
{
    "success": true,
    "sma": $SMA,
    "ecc": $ECC,
    "inc": $INC,
    "raan": $RAAN
}
JSONEOF
    else
        echo "{\"success\": false}" > /tmp/gt_state.json
    fi
else
    echo "{\"success\": false}" > /tmp/gt_state.json
fi

rm -f /tmp/gt_mission.script /tmp/gt_report.txt
chmod 666 /tmp/gt_state.json 2>/dev/null || true

# 5. Launch GMAT
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

echo "=== Task Setup Complete: Ops Log ready ==="