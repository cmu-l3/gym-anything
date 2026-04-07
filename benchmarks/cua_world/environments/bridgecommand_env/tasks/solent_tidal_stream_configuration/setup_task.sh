#!/bin/bash
echo "=== Setting up Solent Tidal Stream Configuration Task ==="

# Define paths
WORLD_DIR="/opt/bridgecommand/World/Solent"
TARGET_FILE="$WORLD_DIR/tidalstream.ini"
TEMPLATE_FILE="/home/ga/Documents/tidal_template.txt"

# Ensure World directory exists (Bridge Command structure)
if [ ! -d "$WORLD_DIR" ]; then
    echo "Creating Solent world directory..."
    mkdir -p "$WORLD_DIR"
fi

# CRITICAL: Grant 'ga' user permission to write to this directory
# /opt is usually root-owned, but agent runs as ga
echo "Setting permissions for agent..."
chown ga:ga "$WORLD_DIR"
chmod 755 "$WORLD_DIR"

# Clean up any previous run artifacts
if [ -f "$TARGET_FILE" ]; then
    echo "Removing existing tidalstream.ini..."
    rm "$TARGET_FILE"
fi

# Create a syntax template for the agent (as a hint/reference)
mkdir -p /home/ga/Documents
cat > "$TEMPLATE_FILE" << 'EOF'
; Bridge Command Tidal Stream Configuration Template
;
; General Settings
Number=1
MeanRangeSprings=4.0
MeanRangeNeaps=2.0

; Stream Definition 1
Lat(1)=50.0000
Long(1)=-1.0000

; Stream Data Points
; Format: Parameter(StreamIndex, HourRelativeToHW) = Value
; Hour range: -6 to +6

; Example for Hour -6
Direction(1,-6)=090
SpeedS(1,-6)=1.5
SpeedN(1,-6)=0.8

; Example for High Water (0)
Direction(1,0)=270
SpeedS(1,0)=1.5
SpeedN(1,0)=0.8
EOF

chown ga:ga "$TEMPLATE_FILE"

# Record start time for file creation verification
date +%s > /tmp/task_start_time.txt

# Launch a terminal or file manager to give agent a starting point
# Start a terminal at the Documents directory
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents &"
    sleep 2
fi

# Maximize terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="