#!/bin/bash
set -e
echo "=== Setting up Scenario Quality Audit Task ==="

# Define paths
SCENARIO_ROOT="/opt/bridgecommand/Scenarios"
SCENARIO_DIR="$SCENARIO_ROOT/h) Humber Approach Training"
DOCS_DIR="/home/ga/Documents"

# Ensure directories exist
mkdir -p "$SCENARIO_DIR"
mkdir -p "$DOCS_DIR"

# 1. Create faulty environment.ini
# Errors: StartTime=25.5 (invalid), StartMonth=15 (invalid), Weather=200.0 (impossible)
cat > "$SCENARIO_DIR/environment.ini" << EOF
Setting=Humber
StartTime=25.5
StartDay=15
StartMonth=15
StartYear=2024
SunRise=6.5
SunSet=18.25
VisibilityRange=8.0
Weather=200.0
RainIntensity=0.0
EOF

# 2. Create faulty ownship.ini
# Errors: Lat/Long is Boston (42/-71) not Humber (53/0), Speed=85.0 (impossible)
cat > "$SCENARIO_DIR/ownship.ini" << EOF
ShipName=MV Humber Trader
InitialLat=42.3601
InitialLong=-71.0589
InitialBearing=270
InitialSpeed=85.0
HasGPS=1
HasDepthSounder=1
EOF

# 3. Create faulty othership.ini
# Errors: 
# - Vessel 2 has identical position to Vessel 1
# - Vessel 2 has 0 legs (cannot move)
# - Vessel 3 (VLCC) has speed 45.0 (impossible)
cat > "$SCENARIO_DIR/othership.ini" << EOF
Number=3

Type(1)=Tanker
InitialLat(1)=53.6350
InitialLong(1)=-0.0500
InitialBearing(1)=180
InitialSpeed(1)=8.0
Legs(1)=2
Bearing(1,1)=180
Speed(1,1)=8.0
Distance(1,1)=3.0
Bearing(1,2)=200
Speed(1,2)=7.0
Distance(1,2)=5.0

Type(2)=Container
InitialLat(2)=53.6350
InitialLong(2)=-0.0500
InitialBearing(2)=0
InitialSpeed(2)=10.0
Legs(2)=0

Type(3)=VLCC Supertanker
InitialLat(3)=53.6200
InitialLong(3)=-0.0300
InitialBearing(3)=90
InitialSpeed(3)=45.0
Legs(3)=2
Bearing(3,1)=90
Speed(3,1)=45.0
Distance(3,1)=5.0
Bearing(3,2)=80
Speed(3,2)=44.0
Distance(3,2)=3.0
EOF

# Set permissions so agent can edit
chown -R ga:ga "$SCENARIO_DIR"
chown -R ga:ga "$DOCS_DIR"

# Remove any pre-existing report
rm -f "$DOCS_DIR/scenario_audit_report.txt"

# Record start time for anti-gaming (file mtime checks)
date +%s > /tmp/task_start_time.txt

# Open the directory in file manager to help the agent get started
if ! pgrep -f "nautilus" > /dev/null; then
    su - ga -c "DISPLAY=:1 nautilus '$SCENARIO_DIR' &"
    sleep 2
fi

# Maximize file manager
DISPLAY=:1 wmctrl -r "Humber Approach Training" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="