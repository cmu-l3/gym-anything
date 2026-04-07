#!/bin/bash
set -e
echo "=== Setting up Vessel Nav Light Setup Task ==="

# Define paths
BC_MODELS="/opt/bridgecommand/Models/Othership"
MODEL_DIR="$BC_MODELS/PilotBoat_ORC"
DOCS_DIR="/home/ga/Documents"
SPEC_FILE="$DOCS_DIR/geometry_spec.txt"
TRUTH_FILE="/tmp/nav_light_ground_truth.json"

# Ensure directories exist
mkdir -p "$MODEL_DIR"
mkdir -p "$DOCS_DIR"

# 1. Create a basic boat.ini (Physics only, NO lights)
cat > "$MODEL_DIR/boat.ini" << EOF
Name=Pilot Boat ORC 171
[Dynamics]
Mass=18000
Damping=2000
RotationalDamping=40000000
BowThrusterForce=5000
SternThrusterForce=0
MaxRudderAngle=35
MaxDriveForce=40000
PropellerOffset=-1.0
RudderOffset=-7.5
EOF

# Set ownership
chown -R ga:ga "$MODEL_DIR"
chown ga:ga "$DOCS_DIR"

# 2. Generate Random Geometry and Ground Truth using Python
# This ensures the agent cannot memorize coordinates; they must read the spec.
python3 -c "
import random
import json

# Randomize dimensions within realistic range
length = round(random.uniform(15.0, 19.0), 1)
beam = round(random.uniform(4.5, 6.0), 1)
half_beam = round(beam / 2.0, 2)

# Define offsets (relative to stern/waterline)
mast_fwd_offset = round(random.uniform(4.0, 6.0), 1)  # Distance from bow
mast_height = round(random.uniform(6.0, 8.0), 1)

cabin_fwd_offset = round(random.uniform(6.0, 8.0), 1) # Distance from bow
cabin_width_offset = round(half_beam - 0.5, 2)
cabin_height = round(random.uniform(3.0, 4.0), 1)

stern_height = round(random.uniform(1.5, 2.5), 1)

# Calculate coordinates
# Origin: Stern, Centerline, Waterline
# X+ Forward, Y+ Starboard, Z+ Up
coord_mast_x = round(length - mast_fwd_offset, 2)
coord_mast_z = mast_height

coord_port_x = round(length - cabin_fwd_offset, 2)
coord_port_y = -cabin_width_offset
coord_port_z = cabin_height

coord_stbd_x = round(length - cabin_fwd_offset, 2)
coord_stbd_y = cabin_width_offset
coord_stbd_z = cabin_height

coord_stern_x = 0.5 # Slightly fwd of transom
coord_stern_z = stern_height

# Generate Spec Text
spec_text = f'''Vessel: ORC 171 Pilot Boat (Variant {random.randint(100,999)})
Coordinate System Specification:
  Origin (0,0,0): Transom (Stern) at waterline on centerline.
  X-axis: Positive Forward (Length).
  Y-axis: Positive Starboard (Right).
  Z-axis: Positive Up (Height).

Dimensions:
  Length Overall: {length}m
  Beam: {beam}m

Light Mounting Points Specification:
  1. Masthead Light:
     - Located on the main mast.
     - {mast_fwd_offset}m aft of the bow.
     - {mast_height}m above the waterline.
     - On the centerline.

  2. Sidelights (Port and Starboard):
     - Located on the wheelhouse roof edges.
     - {cabin_fwd_offset}m aft of the bow.
     - {cabin_width_offset}m laterally from the centerline (one on each side).
     - {cabin_height}m above the waterline.

  3. Sternlight:
     - Located on the transom rail.
     - 0.5m forward of the stern.
     - {stern_height}m above the waterline.
     - On the centerline.
'''

# Generate Ground Truth JSON
ground_truth = {
    'dimensions': {'length': length, 'beam': beam},
    'lights': {
        'masthead': {'x': coord_mast_x, 'y': 0.0, 'z': coord_mast_z, 'color': 'white'},
        'port': {'x': coord_port_x, 'y': coord_port_y, 'z': coord_port_z, 'color': 'red'},
        'starboard': {'x': coord_stbd_x, 'y': coord_stbd_y, 'z': coord_stbd_z, 'color': 'green'},
        'stern': {'x': coord_stern_x, 'y': 0.0, 'z': coord_stern_z, 'color': 'white'}
    }
}

# Write files
with open('$SPEC_FILE', 'w') as f:
    f.write(spec_text)

with open('$TRUTH_FILE', 'w') as f:
    json.dump(ground_truth, f, indent=2)
"

# Set permissions
chown ga:ga "$SPEC_FILE"
chmod 644 "$SPEC_FILE"
# Truth file remains root-owned/hidden or just in /tmp where we assume agent won't look
chmod 644 "$TRUTH_FILE"

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure editor is available (gedit/mousepad/nano)
if ! command -v gedit &> /dev/null && ! command -v mousepad &> /dev/null; then
    apt-get install -y mousepad > /dev/null 2>&1 || true
fi

# Initial screenshot (showing the empty model folder or desktop)
DISPLAY=:1 wmctrl -r "File Manager" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "Setup complete. Geometry spec created at $SPEC_FILE"