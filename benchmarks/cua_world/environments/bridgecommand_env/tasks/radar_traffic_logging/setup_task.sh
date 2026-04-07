#!/bin/bash
echo "=== Setting up radar_traffic_logging task ==="

BC_DATA="/opt/bridgecommand"
SCENARIO_DIR="$BC_DATA/Scenarios/z) Traffic Safety Assessment"

# 1. Create the Scenario Directory
mkdir -p "$SCENARIO_DIR"

# 2. Create environment.ini
# Solent area, daytime, good visibility
cat > "$SCENARIO_DIR/environment.ini" << EOF
Setting="Solent"
StartTime=12.0
VisibilityRange=12.0
Weather=1.0
SeaState=1
StartDay=15
StartMonth=6
StartYear=2024
EOF

# 3. Create ownship.ini
# Heading North (000) at 10 knots
cat > "$SCENARIO_DIR/ownship.ini" << EOF
ShipName="Own Ship"
InitialLat=50.60
InitialLong=-1.10
InitialHeading=0.0
InitialSpeed=10.0
HasGPS=1
HasDepthSounder=1
EOF

# 4. Create othership.ini (The Traffic)
# We define 3 vessels with predictable kinematics for ground truth verification
# Note: 1 degree latitude = 60 nm. 0.01 deg = 0.6 nm.

cat > "$SCENARIO_DIR/othership.ini" << EOF
Number=3

# Vessel 1: MV Sky (Head-on Collision Risk)
# Located directly North, heading South.
# Rel Speed = 20kts. Dist = 3nm (0.05 deg lat).
# CPA should be ~0. TCPA ~ 9 mins.
Type(1)="Container Ship"
InitLat(1)=50.65
InitLong(1)=-1.10
InitialHeading(1)=180.0
InitialSpeed(1)=10.0
Legs(1)=1
Lat(1,1)=50.50
Long(1,1)=-1.10
Speed(1,1)=10.0
Name(1)="MV Sky"

# Vessel 2: Tanker Blue (Crossing Starboard to Port)
# Located North-East.
# Ownship (000, 10k). Target (270, 10k).
# Crossing ahead.
Type(2)="Tanker A"
InitLat(2)=50.62
InitLong(2)=-1.05
InitialHeading(2)=270.0
InitialSpeed(2)=10.0
Legs(2)=1
Lat(2,1)=50.62
Long(2,1)=-1.20
Speed(2,1)=10.0
Name(2)="Tanker Blue"

# Vessel 3: FV Horizon (Parallel/Overtaking)
# Located East, moving same direction but slower.
# Safe.
Type(3)="Fishing Boat"
InitLat(3)=50.60
InitLong(3)=-1.08
InitialHeading(3)=0.0
InitialSpeed(3)=5.0
Legs(3)=1
Lat(3,1)=50.70
Long(3,1)=-1.08
Speed(3,1)=5.0
Name(3)="FV Horizon"
EOF

# 5. Clean up any previous run artifacts
rm -f /home/ga/Documents/traffic_log.csv
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents
chown -R ga:ga "$SCENARIO_DIR"

# 6. Ensure Bridge Command is closed (Agent must launch it)
pkill -f "bridgecommand" 2>/dev/null || true

# 7. Record start time
date +%s > /tmp/task_start_time.txt

# 8. Initial screenshot (Desktop state)
DISPLAY=:1 wmctrl -k on  # Show desktop
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Scenario 'z) Traffic Safety Assessment' created."