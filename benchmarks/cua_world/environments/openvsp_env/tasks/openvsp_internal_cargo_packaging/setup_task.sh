#!/bin/bash
# Setup script for openvsp_internal_cargo_packaging task
# Prepares the eCRM-001 model, creates the spec sheet, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_internal_cargo_packaging ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the packaging specification document
cat > /home/ga/Desktop/packaging_spec.txt << 'SPEC_EOF'
============================================================
  eCRM-001 INTERNAL CARGO PACKAGING SPECIFICATION
  Document: PKG-eCRM-002  Rev B
  Issued by: Advanced Concepts Group
  Units: Metric (meters)
============================================================

Objective:
Model standard LD3/rectangular freight proxy blocks and 
position them inside the lower fuselage lobe for clearance 
checking.

Proxy 1: FORWARD CARGO HOLD (FwdCargo)
--------------------------------------
Component Type : Fuselage (or Pod)
Component Name : FwdCargo
Total Length   : 4.8 m
Cross-Section  : Rectangular (or Rounded Rectangle)
  - Width      : 1.5 m
  - Height     : 1.1 m
Position (X_Rel): 10.5 m
Position (Z_Rel): -1.2 m

Proxy 2: AFT CARGO HOLD (AftCargo)
--------------------------------------
Component Type : Fuselage (or Pod)
Component Name : AftCargo
Total Length   : 3.2 m
Cross-Section  : Rectangular (or Rounded Rectangle)
  - Width      : 1.5 m
  - Height     : 1.1 m
Position (X_Rel): 22.0 m
Position (Z_Rel): -1.0 m

Instructions:
1. Add these components to the master OpenVSP model.
2. Ensure you modify the intermediate cross-sections 
   from the default Circular shape to Rectangular.
3. Save the completed model exactly as:
   /home/ga/Documents/OpenVSP/eCRM001_packaged.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/packaging_spec.txt
chmod 644 /home/ga/Desktop/packaging_spec.txt

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any previous packaged model outputs to prevent gaming
rm -f "$MODELS_DIR/eCRM001_packaged.vsp3"
rm -f /tmp/openvsp_packaging_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time — agent may need to launch it manually."
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="