#!/bin/bash
# Setup script for openvsp_multi_section_sailplane task
# Creates planform spec document on Desktop, clears old outputs, launches OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_multi_section_sailplane ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the sailplane wing specification document
cat > /home/ga/Desktop/sailplane_planform.txt << 'SPEC_EOF'
15-METER STANDARD CLASS SAILPLANE WING SPECIFICATION
====================================================
Target: Approximate elliptical lift distribution using a 4-section multi-taper wing.

Note: The "Span" dimensions below are for the HALF-SPAN (one side of the wing) 
as expected by OpenVSP's individual Section parameter inputs.

Section 1 (Root, innermost):
  Span: 2.00 m
  Root Chord: 0.90 m
  Tip Chord:  0.86 m
  Sweep (LE): 0.0 deg

Section 2:
  Span: 2.50 m
  Root Chord: 0.86 m
  Tip Chord:  0.70 m
  Sweep (LE): 1.0 deg

Section 3:
  Span: 1.80 m
  Root Chord: 0.70 m
  Tip Chord:  0.45 m
  Sweep (LE): 2.5 deg

Section 4 (Tip, outermost):
  Span: 1.20 m
  Root Chord: 0.45 m
  Tip Chord:  0.15 m
  Sweep (LE): 5.0 deg

Overall Target Verification:
  Total Span (both sides combined): 15.00 m
  Overall Planform Area: ~10.21 m^2
====================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/sailplane_planform.txt
chmod 644 /home/ga/Desktop/sailplane_planform.txt

# Remove any previous model
rm -f "$MODELS_DIR/sailplane_15m.vsp3"
rm -f /tmp/openvsp_multi_section_sailplane_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP
launch_openvsp
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