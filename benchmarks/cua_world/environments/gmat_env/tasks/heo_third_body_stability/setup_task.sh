#!/bin/bash
set -euo pipefail

echo "=== Setting up heo_third_body_stability task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean workspace
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/GMAT_output
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create mission specification document
cat > /home/ga/Desktop/exhea_mission_spec.txt << 'SPECEOF'
=========================================================
EXHEA (EXplorer for High-Energy Astrophysics)
PRELIMINARY ORBIT DESIGN SPECIFICATION
=========================================================

MISSION DURATION: 5 Years (1825 Days)
INITIAL EPOCH: 01 Mar 2026 12:00:00.000 UTC

SPACECRAFT PROPERTIES:
- Dry Mass: 850 kg
- Drag Area: 4.5 m^2 (Note: Disable drag for stability analysis)

BASELINE ORBITAL ELEMENTS (EarthMJ2000Eq):
- SMA: 81878.14 km
- ECC: 0.909889
- INC: 55.0 deg
- RAAN: 0.0 deg  <-- BASELINE VALUE (Must be optimized for stability)
- AOP: 90.0 deg
- TA: 0.0 deg

Note: The baseline orbit has an initial perigee altitude of approximately 1000 km.
Due to the high eccentricity and inclination, Kozai-Lidov effects driven by 
Lunar and Solar gravity are expected to be severe.
=========================================================
SPECEOF
chown ga:ga /home/ga/Desktop/exhea_mission_spec.txt

# 4. Create internal Ground Truth baseline script to calculate true crash day
echo "Calculating Ground Truth baseline..."
cat > /tmp/baseline_heo.script << 'EOF'
Create Spacecraft EXHEA;
GMAT EXHEA.DateFormat = UTCGregorian;
GMAT EXHEA.Epoch = '01 Mar 2026 12:00:00.000';
GMAT EXHEA.CoordinateSystem = EarthMJ2000Eq;
GMAT EXHEA.DisplayStateType = Keplerian;
GMAT EXHEA.SMA = 81878.14;
GMAT EXHEA.ECC = 0.909889;
GMAT EXHEA.INC = 55.0;
GMAT EXHEA.RAAN = 0.0;
GMAT EXHEA.AOP = 90.0;
GMAT EXHEA.TA = 0.0;
GMAT EXHEA.DryMass = 850;
GMAT EXHEA.Cd = 2.2;
GMAT EXHEA.Cr = 1.8;
GMAT EXHEA.DragArea = 4.5;
GMAT EXHEA.SRPArea = 4.5;

Create ForceModel FM;
GMAT FM.CentralBody = Earth;
GMAT FM.PrimaryBodies = {Earth};
GMAT FM.PointMasses = {Luna, Sun};
GMAT FM.GravityField.Earth.Degree = 0;
GMAT FM.GravityField.Earth.Order = 0;
GMAT FM.Drag.AtmosphereModel = None;
GMAT FM.SRP = Off;

Create Propagator Prop;
GMAT Prop.FM = FM;
GMAT Prop.Type = RungeKutta89;
GMAT Prop.InitialStepSize = 60;
GMAT Prop.Accuracy = 1e-011;
GMAT Prop.MinStep = 0.001;
GMAT Prop.MaxStep = 86400;
GMAT Prop.StopIfAccuracyIsViolated = true;

Create ReportFile Rep;
GMAT Rep.Filename = '/tmp/baseline_report.txt';
GMAT Rep.Add = {EXHEA.ElapsedDays, EXHEA.Earth.Altitude};
GMAT Rep.WriteHeaders = false;

BeginMissionSequence;
Propagate Prop(EXHEA) {EXHEA.ElapsedDays = 1825, EXHEA.Earth.Altitude = 120};
EOF

# Run baseline script to get exact Truth Day
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
TRUTH_DAYS="0"
if [ -n "$CONSOLE" ]; then
    timeout 60 "$CONSOLE" --run /tmp/baseline_heo.script > /tmp/gmat_baseline.log 2>&1 || true
    if [ -f /tmp/baseline_report.txt ]; then
        LAST_LINE=$(tail -n 1 /tmp/baseline_report.txt | tr -s ' ' | sed 's/^ *//' || echo "")
        TRUTH_DAYS=$(echo "$LAST_LINE" | cut -d' ' -f1 || echo "0")
    fi
fi
echo "$TRUTH_DAYS" > /tmp/baseline_truth.txt
echo "Ground Truth Baseline Crash Day: $TRUTH_DAYS"

# 5. Launch GMAT GUI
echo "Launching GMAT GUI..."
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