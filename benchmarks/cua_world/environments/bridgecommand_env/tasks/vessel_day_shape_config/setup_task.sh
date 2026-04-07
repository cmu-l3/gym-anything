#!/bin/bash
echo "=== Setting up Vessel Day Shape Config Task ==="

# Define paths
BC_ROOT="/opt/bridgecommand"
MODEL_DIR="$BC_ROOT/Models/Ownship/Dredger"
SHAPES_DIR="$BC_ROOT/Models/Shapes"

# Ensure directories exist
mkdir -p "$MODEL_DIR"
mkdir -p "$SHAPES_DIR"

# Create dummy 3D shape files if they don't exist (agent needs to reference them)
# In a real env, these might be actual assets, but for config testing, existence is enough.
touch "$SHAPES_DIR/ball.3ds"
touch "$SHAPES_DIR/diamond.3ds"
touch "$SHAPES_DIR/cone.3ds"
touch "$SHAPES_DIR/cylinder.3ds"

# Create the base boat.ini file for the Dredger
# This represents a basic vessel definition without day shapes
cat > "$MODEL_DIR/boat.ini" << EOF
[General]
Name="Trailing Suction Hopper Dredger"
Description="A medium sized dredger for channel maintenance."
Type="Dredger"

[Geometry]
Length=80.0
Beam=14.0
Draft=5.5
Mass=4000000

[Dynamics]
MaxSpeed=12.0
TurnRate=1.5
EnginePower=3000

[Graphics]
Model="Models/Ownship/Generic/hull.3ds"
Scale=1.0

# --- Visual Signals ---
# Add day shapes below using Shape(n) and ShapeOffset(n)
# Mast is located at X=0.0, Y=5.0, Z=12.0 (Top)

EOF

# Set permissions so agent can edit
chown -R ga:ga "$MODEL_DIR"
chown -R ga:ga "$SHAPES_DIR"

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Record initial file hash to detect modification
md5sum "$MODEL_DIR/boat.ini" > /tmp/initial_boat_ini_checksum.txt

# Launch a file explorer to help the agent find the location
if ! pgrep -f "nautilus" > /dev/null; then
    su - ga -c "DISPLAY=:1 nautilus '$MODEL_DIR' &"
fi

# Wait for window
sleep 2

# Take initial screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Dredger model created at $MODEL_DIR"
echo "Shape assets ensured at $SHAPES_DIR"