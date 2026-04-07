#!/bin/bash
# Setup script for openvsp_external_stores_integration task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_external_stores_integration ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chown ga:ga "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Write the specification memo
cat > /home/ga/Desktop/external_stores_spec.txt << 'SPEC_EOF'
MEMORANDUM
To: Aerodynamics Pre-Processing Team
From: Chief Engineer, Special Missions
Subject: eCRM-001 External Fuel Tanks Integration

We are proceeding with the maritime patrol derivative of the eCRM-001.
Please add the underwing external fuel tanks to the OpenVSP model and re-run the wetted area analysis.

TANK SPECIFICATIONS:
- Component Type: Pod
- Length: 7.5 meters
- Fineness Ratio: 5.0 (Max Diameter = 1.5 m)

POSITIONING (Relative to Origin):
- X Location: 28.0 m
- Y Location: 9.0 m
- Z Location: -1.8 m

SYMMETRY:
- The tank must be mirrored to the other wing (Enable Planar Y Symmetry in the Symmetry tab).

DELIVERABLES:
1. Save the updated model to: /home/ga/Documents/OpenVSP/eCRM001_military.vsp3
2. Run CompGeom and record the new Total Wetted Area in: /home/ga/Desktop/stores_report.txt
SPEC_EOF

chown ga:ga /home/ga/Desktop/external_stores_spec.txt
chmod 644 /home/ga/Desktop/external_stores_spec.txt

# Remove any stale output files
rm -f "$MODELS_DIR/eCRM001_military.vsp3"
rm -f /home/ga/Desktop/stores_report.txt
rm -f /tmp/openvsp_stores_result.json

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Kill any running OpenVSP instance
kill_openvsp

# Launch OpenVSP with the baseline model
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

echo "=== Setup complete: eCRM-001 ready for modification ==="