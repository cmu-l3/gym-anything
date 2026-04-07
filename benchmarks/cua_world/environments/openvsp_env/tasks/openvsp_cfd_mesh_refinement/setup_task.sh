#!/bin/bash
# Setup script for openvsp_cfd_mesh_refinement
# Prepares the eCRM-001 model, creates the spec file, and launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_cfd_mesh_refinement ==="

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p "$EXPORTS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy clean model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Write the mesh refinement specification document
cat > /home/ga/Desktop/mesh_refinement_spec.txt << 'SPEC_EOF'
============================================================
  CFD MESH REFINEMENT SPECIFICATION
  Target: eCRM-001 Transonic Drag Assessment
  Region: Empennage / Horizontal Stabilizer Wake
============================================================

1. Global Mesh Settings
-----------------------
Base/Global Max Edge Length :  0.40 m

2. Local Refinement Source
--------------------------
Source Type                 :  Box
Target Edge Length          :  0.05 m

3. Box Center Coordinates (Model Origin Reference)
--------------------------------------------------
X (Streamwise)              :  52.0 m
Y (Spanwise)                :   0.0 m
Z (Vertical)                :   5.0 m

4. Box Extents (Dimensions)
---------------------------
Length (X-direction)        :  10.0 m
Width (Y-direction)         :  18.0 m
Height (Z-direction)        :   8.0 m

INSTRUCTIONS:
- Create this Box source in OpenVSP's CFD Mesh > Sources tab.
- Run the mesh generator.
- Export as Cart3D (.tri) to ~/Documents/OpenVSP/exports/eCRM001_refined.tri
- Save the VSP3 model as ~/Documents/OpenVSP/eCRM001_mesh_setup.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/mesh_refinement_spec.txt
chmod 644 /home/ga/Desktop/mesh_refinement_spec.txt

# Remove any stale output files the agent might create
rm -f "$MODELS_DIR/eCRM001_mesh_setup.vsp3"
rm -f "$EXPORTS_DIR/eCRM001_refined.tri"
rm -f /tmp/openvsp_cfd_mesh_result.json

# Kill any running OpenVSP instance
kill_openvsp

# Launch OpenVSP with the model
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete: eCRM-001 ready ==="