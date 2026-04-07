#!/bin/bash
# Setup script for openvsp_control_surface_layout task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_control_surface_layout ==="

# Ensure working directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Remove any pre-existing output file
rm -f "$MODELS_DIR/eCRM001_with_controls.vsp3"
rm -f /tmp/openvsp_control_surface_result.json

# Write the control surface specification document
cat > /home/ga/Desktop/control_surface_spec.txt << 'SPEC_EOF'
Control Surface Allocation – eCRM-001
======================================
Project: Regional Transport Research Configuration
Prepared by: Chief Designer – Flight Controls Group
Date: 2024-11-15

All sub-surfaces shall be added as "Control Surface" (SS_Control) type
in OpenVSP's Sub-Surface panel for the appropriate parent component.

Surface 1: INBOARD FLAP
  Parent Component : Wing
  Spanwise Start   : 0.10  (fraction of half-span, 0=root, 1=tip)
  Spanwise End     : 0.42
  Chord Hinge Line : 72% chord from LE (i.e., trailing 28% of chord)
  Surface Tag      : Flap

Surface 2: OUTBOARD AILERON
  Parent Component : Wing
  Spanwise Start   : 0.64
  Spanwise End     : 0.96
  Chord Hinge Line : 76% chord from LE (i.e., trailing 24% of chord)
  Surface Tag      : Aileron

Surface 3: ELEVATOR
  Parent Component : Horiz (horizontal stabilizer)
  Spanwise Start   : 0.08
  Spanwise End     : 0.92
  Chord Hinge Line : 62% chord from LE (i.e., trailing 38% of chord)
  Surface Tag      : Elevator

NOTES:
- Use "Control Surface" sub-surface type for all three
- Ensure symmetry is maintained (OpenVSP mirrors automatically for symmetric components)
- Save the completed model as: eCRM001_with_controls.vsp3
  in /home/ga/Documents/OpenVSP/
SPEC_EOF

chown ga:ga /home/ga/Desktop/control_surface_spec.txt
chmod 644 /home/ga/Desktop/control_surface_spec.txt

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (crucial for anti-gaming)
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
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="