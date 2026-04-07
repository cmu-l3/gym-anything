#!/bin/bash
set -e

echo "=== Setting up Ship Hydrodynamics Calibration Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Define paths
SHIP_DIR="/opt/bridgecommand/Models/Ship/MV_Gladiator"
DOCS_DIR="/home/ga/Documents"
INI_FILE="$SHIP_DIR/dynamics.ini"

# Ensure directories exist
mkdir -p "$SHIP_DIR"
mkdir -p "$DOCS_DIR"

# 1. Create the Sea Trials Report
cat > "$DOCS_DIR/Sea_Trials_Report_2025.txt" << 'EOF'
OFFICIAL SEA TRIALS REPORT - MV GLADIATOR
Date: Jan 15, 2025
Location: North Sea

VESSEL PARTICULARS:
Length Overall (LOA): 541.3 feet
Beam: 75.5 feet
Displacement: 15,000 Tonnes

PERFORMANCE TRIALS:
1. Turning Circle Test
   Conditions: Calm sea, Speed 14.0 knots.
   Result: Tactical Diameter was measured at 3.2 cables.

2. Speed Trials
   Conditions: Max continuous thrust (850 kN).
   Result: Vessel achieved a stable top speed of 19.5 knots.

Notes:
- All turning tests performed with full rudder (35 degrees).
- 1 Cable = 185.2 meters.
EOF

# 2. Create the Physics Tech Note
cat > "$DOCS_DIR/Sim_Physics_Tech_Note.txt" << 'EOF'
BRIDGE COMMAND PHYSICS ENGINE - CALIBRATION FORMULAS
CONFIDENTIAL - FOR TECHNICIAN USE ONLY

The simulator uses the following simplified hydrodynamic formulas. Use these to derive the correct coefficients for the .ini files.

1. UNIT STANDARDS
   - All Mass in kg (1 Tonne = 1000 kg)
   - All Distances in Meters
   - All Forces in Newtons (1 kN = 1000 N)
   - All Speeds in Meters per Second (1 Knot = 0.5144 m/s)

2. TURNING GEOMETRY
   To calibrate the turning circle, use the "Tactical Diameter" formula:
   
   RudderArea = (3.0 * Mass * Velocity) / (TacticalDiameter * 1200)

   Where:
   - Velocity is the speed entering the turn (m/s)
   - TacticalDiameter is the diameter of the turn (m)
   - Mass is vessel mass (kg)
   - 1200 is the fluid density constant for this engine

3. DRAG & TOP SPEED
   At top speed, Thrust equals Drag.
   
   DragForce = 0.5 * WaterDensity * DragArea * Velocity^2
   
   Where:
   - WaterDensity = 1025 kg/m^3
   - Velocity is top speed (m/s)
   - DragForce equals MaxThrust at top speed
   
   Solve for DragArea to limit the ship to its rated top speed.
EOF

# 3. Create the uncalibrated (bad) dynamics.ini
# Note: Mass is already in kg (15,000 tonnes * 1000) to simplify one step and avoid ambiguity
cat > "$INI_FILE" << 'EOF'
[General]
Name=MV Gladiator
Description=Placeholder model for training - UNCALIBRATED
Mass=15000000
Length=100.0
Beam=15.0

[Dynamics]
; These are the placeholder values that must be fixed
RudderArea=25.0
DragArea=50.0
MaxThrust=850000
MaxRudderAngle=35
EOF

# Set permissions
chown -R ga:ga "$SHIP_DIR"
chown -R ga:ga "$DOCS_DIR"

# Ensure Text Editor is available (gedit or similar)
if ! command -v gedit &> /dev/null; then
    echo "Installing gedit for text editing..."
    apt-get update && apt-get install -y gedit
fi

# Open the file manager to Documents to help the agent start
if pgrep -f "nautilus" > /dev/null; then
    pkill -f "nautilus"
fi
su - ga -c "DISPLAY=:1 nautilus /home/ga/Documents &"

# Wait for window
sleep 3
DISPLAY=:1 wmctrl -r "Documents" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="