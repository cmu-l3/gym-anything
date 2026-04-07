#!/bin/bash
set -euo pipefail

echo "=== Setting up lunar_orbiter_earth_eclipse task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -rf /home/ga/GMAT_output
rm -f /home/ga/Documents/missions/lunar_baseline.script
rm -f /home/ga/Desktop/Power_Analysis_Memo.txt

mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Create the requirements memo
cat > /home/ga/Desktop/Power_Analysis_Memo.txt << 'MEMOEOF'
MEMORANDUM
To: Mission Analysis Team
From: Power Systems Engineering
Date: Feb 28, 2025
Subject: March 2025 Total Lunar Eclipse Battery Assessment

We have a Total Lunar Eclipse occurring on March 14, 2025. The spacecraft is in a 100 km circular lunar orbit. Normally, the spacecraft experiences about 45 minutes of eclipse (lunar night) per 118-minute orbit, and our batteries are sized for this.

However, during the March 14 eclipse, the Earth will cast a massive shadow over the entire lunar system. We need to know the maximum continuous eclipse duration (Umbra) the spacecraft will experience so we can determine if the batteries will survive.

Please modify the `lunar_baseline.script` to:
1. Create an EclipseLocator.
2. Ensure both the Earth and Luna are set as OccultingBodies (this is critical—if you only use Luna, you will miss the Earth's shadow!).
3. Output the report to `/home/ga/GMAT_output/EclipseReport.txt`.
4. Propagate the spacecraft for at least 3 days to cover the event.

Once run, look at the report, find the longest single Umbra duration, and save it in `/home/ga/GMAT_output/eclipse_analysis.json` formatted like:
{
  "max_umbra_duration_seconds": 4500.5
}
MEMOEOF
chown ga:ga /home/ga/Desktop/Power_Analysis_Memo.txt

# 4. Create the baseline script
cat > /home/ga/Documents/missions/lunar_baseline.script << 'GMATEOF'
%----------------------------------------
%---------- Spacecraft
%----------------------------------------
Create Spacecraft LunarSat;
GMAT LunarSat.DateFormat = UTCGregorian;
GMAT LunarSat.Epoch = '13 Mar 2025 00:00:00.000';
GMAT LunarSat.CoordinateSystem = MoonEq;
GMAT LunarSat.DisplayStateType = Keplerian;
GMAT LunarSat.SMA = 1838.14;
GMAT LunarSat.ECC = 0.0001;
GMAT LunarSat.INC = 90.0;
GMAT LunarSat.RAAN = 0.0;
GMAT LunarSat.AOP = 0.0;
GMAT LunarSat.TA = 0.0;

%----------------------------------------
%---------- ForceModels
%----------------------------------------
Create ForceModel MoonProp_ForceModel;
GMAT MoonProp_ForceModel.CentralBody = Luna;
GMAT MoonProp_ForceModel.PointMasses = {Luna, Earth, Sun};
GMAT MoonProp_ForceModel.Drag = None;
GMAT MoonProp_ForceModel.SRP = Off;

%----------------------------------------
%---------- Propagators
%----------------------------------------
Create Propagator MoonProp;
GMAT MoonProp.FM = MoonProp_ForceModel;
GMAT MoonProp.Type = RungeKutta89;
GMAT MoonProp.InitialStepSize = 60;
GMAT MoonProp.Accuracy = 9.999999999999999e-012;
GMAT MoonProp.MinStep = 0.001;
GMAT MoonProp.MaxStep = 2700;

%----------------------------------------
%---------- Coordinate Systems
%----------------------------------------
Create CoordinateSystem MoonEq;
GMAT MoonEq.Origin = Luna;
GMAT MoonEq.Axes = BodyEquator;

%----------------------------------------
%---------- Mission Sequence
%----------------------------------------
BeginMissionSequence;
% ADD YOUR ECLIPSE LOCATOR AND PROPAGATE COMMANDS BELOW:


GMATEOF
chown ga:ga /home/ga/Documents/missions/lunar_baseline.script

# 5. Launch GMAT with the baseline script open
echo "Launching GMAT..."
launch_gmat "/home/ga/Documents/missions/lunar_baseline.script"

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