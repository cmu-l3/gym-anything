#!/bin/bash
# Setup script for openvsp_twin_boom_uav task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_twin_boom_uav ==="

mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the specification document
cat > /home/ga/Desktop/rq7_shadow_spec.txt << 'SPEC_EOF'
============================================================
  TACTICAL UAV CONCEPT - GEOMETRY SPECIFICATION
  Reference: RQ-7 Shadow class twin-boom pusher
  Units: Metric (meters)
============================================================

Overview:
Twin-boom configuration with a central pod, a main wing, 
two off-axis tail booms, and a horizontal stabilizer bridging the booms.

1. Central Pod
   - Component: Fuselage
   - Length: 3.4 m
   - Location: Centered at Origin (X=0, Y=0)

2. Main Wing
   - Component: Wing
   - Total Span: 4.3 m
   - Location: Translated aft to X = 1.0 m, Y = 0

3. Tail Booms
   - Component: Fuselage (or Pod)
   - Length: 2.5 m
   - Location: 
     - X = 1.0 m (starts at the main wing)
     - Y = offset laterally to 0.65 m from centerline
   - Note: Use planar symmetry (XZ plane) to generate the opposite boom, 
     or manually create a second boom at Y = -0.65 m.

4. Horizontal Stabilizer (Tail)
   - Component: Wing
   - Total Span: 1.3 m (must exactly match the separation distance between the booms)
   - Location: Translated aft to X = 3.5 m (at the end of the tail booms), Y = 0

Save the completed model as:
/home/ga/Documents/OpenVSP/twin_boom_uav.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/rq7_shadow_spec.txt
chmod 644 /home/ga/Desktop/rq7_shadow_spec.txt

# Remove any stale output files
rm -f "$MODELS_DIR/twin_boom_uav.vsp3"
rm -f /tmp/task_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time

# Launch blank OpenVSP
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="