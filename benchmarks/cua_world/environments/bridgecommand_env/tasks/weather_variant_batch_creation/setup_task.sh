#!/bin/bash
set -e
echo "=== Setting up Meteorological Variant Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

SCENARIO_DIR="/opt/bridgecommand/Scenarios"
MASTER_DIR="$SCENARIO_DIR/00_Master_Assessment"
DOCS_DIR="/home/ga/Documents"

# Ensure directories exist and are clean
mkdir -p "$DOCS_DIR"
rm -rf "$SCENARIO_DIR"/0*_Assessment_* 2>/dev/null || true
rm -f "$DOCS_DIR/scenario_manifest.csv"

# Create Master Scenario Directory
mkdir -p "$MASTER_DIR"

# Randomize base speed (12.0 to 20.0) to prevent hardcoding
# This forces the agent to actually read the file
BASE_INT=$(shuf -i 12-20 -n 1)
DECIMAL=$(shuf -i 0-9 -n 1)
BASE_SPEED="${BASE_INT}.${DECIMAL}"

echo "Generated Base Speed: $BASE_SPEED"
echo "$BASE_SPEED" > /tmp/base_speed_truth.txt

# Create environment.ini
cat > "$MASTER_DIR/environment.ini" << EOF
Setting=Solent
StartTime=10.0
StartDay=15
StartMonth=6
StartYear=2024
VisibilityRange=12.0
Weather=1.0
RainVisible=0
Fog=0
EOF

# Create ownship.ini
cat > "$MASTER_DIR/ownship.ini" << EOF
ShipName=Training Vessel
Type=Ferry
InitialLat=50.75
InitialLong=-1.20
InitialBearing=090
InitialSpeed=$BASE_SPEED
EOF

# Create othership.ini (placeholder)
cat > "$MASTER_DIR/othership.ini" << EOF
Number=1
Type(0)=Buoy
InitialLat(0)=50.76
InitialLong(0)=-1.19
EOF

# Set permissions so 'ga' user can access and create files
chown -R ga:ga "$SCENARIO_DIR"
chown -R ga:ga "$DOCS_DIR"
chmod -R 777 "$SCENARIO_DIR" 

# Capture initial state screenshot
# We open the file manager to show the starting state
if ! pgrep -f "nautilus" > /dev/null; then
    su - ga -c "DISPLAY=:1 nautilus '$MASTER_DIR' &"
    sleep 3
fi

# Maximize file manager
DISPLAY=:1 wmctrl -r "Files" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="