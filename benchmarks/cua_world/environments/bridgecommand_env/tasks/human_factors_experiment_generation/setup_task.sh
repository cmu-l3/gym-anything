#!/bin/bash
set -e
echo "=== Setting up Human Factors Experiment Generation Task ==="

# 1. Cleanup previous runs
rm -rf "/opt/bridgecommand/Scenarios/z) Experiment_Batch_2026" 2>/dev/null || true
rm -rf "/home/ga/Documents/Base_Scenario_Config" 2>/dev/null || true
rm -f "/home/ga/Documents/experimental_design.txt" 2>/dev/null || true
rm -f "/home/ga/Documents/experiment_manifest.csv" 2>/dev/null || true

mkdir -p "/home/ga/Documents/Base_Scenario_Config"
chown ga:ga "/home/ga/Documents/Base_Scenario_Config"

# 2. Create Base Scenario Files
# environment.ini
cat > "/home/ga/Documents/Base_Scenario_Config/environment.ini" << EOF
Setting="Solent"
StartTime=10.0
StartDay=15
StartMonth=6
StartYear=2025
Weather=1.0
VisibilityRange=12.0
SeaState=1
Rain=0
EOF

# ownship.ini
cat > "/home/ga/Documents/Base_Scenario_Config/ownship.ini" << EOF
ShipName="Research Vessel"
InitialLat=50.78
InitialLong=-1.12
InitialBearing=90
InitialSpeed=10
HasGPS=1
HasDepthSounder=1
EOF

# othership.ini (1 vessel)
cat > "/home/ga/Documents/Base_Scenario_Config/othership.ini" << EOF
Number=1
Type(1)="Container"
InitLat(1)=50.78
InitLong(1)=-1.08
InitBearing(1)=270
Speed(1)=12
Legs(1)=1
Lat(1,1)=50.78
Long(1,1)=-1.20
EOF

# Set permissions for base files
chown -R ga:ga "/home/ga/Documents/Base_Scenario_Config"

# 3. Create Experimental Brief
cat > "/home/ga/Documents/experimental_design.txt" << EOF
EXPERIMENTAL DESIGN BRIEF: PROJECT HF-2026
------------------------------------------
Study: OOW Workload under Restricted Visibility
Factor A: Visibility (Low=0.5nm, High=12.0nm)
Factor B: Traffic Density (Low=1 vessel, High=4 vessels)

REQUIRED SCENARIO BATCH:
Please generate the following 4 scenarios in /opt/bridgecommand/Scenarios/z) Experiment_Batch_2026/:

1. Directory: "Cond_A_LoVis_LoTraf"
   - Visibility: 0.5
   - Total Vessels: 1 (Target Only)

2. Directory: "Cond_B_LoVis_HiTraf"
   - Visibility: 0.5
   - Total Vessels: 4 (Target + 3 Distractors)

3. Directory: "Cond_C_HiVis_LoTraf"
   - Visibility: 12.0
   - Total Vessels: 1 (Target Only)

4. Directory: "Cond_D_HiVis_HiTraf"
   - Visibility: 12.0
   - Total Vessels: 4 (Target + 3 Distractors)

NOTES:
- Use the Base Scenario in /home/ga/Documents/Base_Scenario_Config/ as the template.
- For High Traffic, replicate the target vessel 3 times to create distractors (ensure unique indices).
- Create a manifest CSV at /home/ga/Documents/experiment_manifest.csv documenting the created files.
EOF
chown ga:ga "/home/ga/Documents/experimental_design.txt"

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Ensure Bridge Command is closed (this is a file generation task)
pkill -f "bridgecommand" 2>/dev/null || true

# 6. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="