#!/bin/bash
echo "=== Setting up import_dxf_nema17_gasket task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
WORKSPACE_DIR="/home/ga/Documents/SolveSpace"
mkdir -p "$WORKSPACE_DIR"

# Clean up any files from previous runs
rm -f "$WORKSPACE_DIR/nema17_damper_profile.dxf"
rm -f "$WORKSPACE_DIR/nema17_damper_3d.slvs"
rm -f "$WORKSPACE_DIR/nema17_damper_3d.stl"

# Generate a realistic DXF profile of a NEMA 17 face (42.3 x 42.3 mm)
# using Python, writing directly to the workspace directory.
echo "Generating NEMA 17 DXF profile..."
python3 -c "
import os

filepath = '$WORKSPACE_DIR/nema17_damper_profile.dxf'
with open(filepath, 'w') as f:
    f.write('0\nSECTION\n2\nENTITIES\n')
    
    # 42.3 x 42.3 square outline
    pts = [(-21.15, -21.15), (21.15, -21.15), (21.15, 21.15), (-21.15, 21.15)]
    for i in range(4):
        x1, y1 = pts[i]
        x2, y2 = pts[(i+1)%4]
        f.write(f'0\nLINE\n8\n0\n10\n{x1}\n20\n{y1}\n11\n{x2}\n21\n{y2}\n')
        
    # Center bore (22mm diameter -> 11mm radius)
    f.write(f'0\nCIRCLE\n8\n0\n10\n0.0\n20\n0.0\n40\n11.0\n')
    
    # 4 Mounting holes (M3 clearance -> 1.5mm radius), spaced 31mm apart
    for x, y in [(-15.5, -15.5), (15.5, -15.5), (15.5, 15.5), (-15.5, 15.5)]:
        f.write(f'0\nCIRCLE\n8\n0\n10\n{x}\n20\n{y}\n40\n1.5\n')
        
    f.write('0\nENDSEC\n0\nEOF\n')
print(f'Created {filepath}')
"

# Set permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Initial state screenshot saved to /tmp/task_initial.png"

echo "=== Setup complete ==="