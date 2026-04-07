#!/bin/bash
# Setup script for openvsp_subsurface_solar_array
# Prepares the base model, writes the spec file, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_subsurface_solar_array ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy base model (eCRM-001 renamed to hale_uav for context)
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/hale_uav.vsp3"
chmod 644 "$MODELS_DIR/hale_uav.vsp3"
chown ga:ga "$MODELS_DIR/hale_uav.vsp3"

# Write the SubSurface specification document
cat > /home/ga/Desktop/subsurface_spec.txt << 'SPEC_EOF'
HALE UAV SubSurface Definition Specification
============================================

Target Component: Wing
1. Name: Solar_Array_Inboard
   Type: Rectangle
   U Start: 0.55
   U End: 0.85
   W Start: 0.05
   W End: 0.45

2. Name: Solar_Array_Outboard
   Type: Rectangle
   U Start: 0.55
   U End: 0.85
   W Start: 0.55
   W End: 0.95

Target Component: Horiz_Tail
3. Name: Morphing_Hinge
   Type: Line
   U Start: 0.75
   U End: 0.75
   W Start: 0.10
   W End: 0.90

Notes:
- Use the 'Sub' tab in the component geometry window to add these.
- Select the correct Target Component before adding the SubSurfaces.
- Save the file as hale_uav_subsurfaces.vsp3.
- Run Degen Geom and export to exports/hale_uav_degengeom.csv.
SPEC_EOF

chown ga:ga /home/ga/Desktop/subsurface_spec.txt
chmod 644 /home/ga/Desktop/subsurface_spec.txt

# Remove any previous output models and exports
rm -f "$MODELS_DIR/hale_uav_subsurfaces.vsp3"
rm -f "$EXPORTS_DIR/hale_uav_degengeom.csv"
rm -f /tmp/openvsp_subsurface_solar_array_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Launch OpenVSP with the base model
launch_openvsp "$MODELS_DIR/hale_uav.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="