#!/bin/bash
# Setup script for openvsp_sounding_rocket_model task
# Creates the rocket specification document on the Desktop and launches a blank OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_sounding_rocket_model ==="

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the rocket specification document
cat > /home/ga/Desktop/rocket_spec.txt << 'SPEC_EOF'
===============================================
  SPARTAN-IV Sounding Rocket Geometry Spec
  Spaceport America Cup 2025 Entry
  Document: GEO-2025-004 Rev B
===============================================

COORDINATE SYSTEM
  Origin at nose tip, X-axis aft along body centerline
  All dimensions in meters

NOSE CONE
  Profile: Ogive (or conical approximation)
  Length:  0.50 m
  Base Diameter: 0.152 m (6.0 in)

BODY TUBE (CYLINDRICAL SECTION)
  Length:  1.60 m
  Outer Diameter: 0.152 m (constant)

BOAT TAIL (AFT TRANSITION)
  Length:  0.30 m
  Forward Diameter: 0.152 m
  Aft Diameter: 0.102 m (4.0 in)

TOTAL BODY LENGTH: 2.40 m (nose tip to aft end)

STABILIZATION FINS (x4, equally spaced at 90 deg)
  Quantity: 4
  Planform: Trapezoidal
  Root Chord: 0.25 m
  Tip Chord: 0.08 m
  Semi-Span (from body surface): 0.13 m
  Sweep (leading edge): 35 deg
  Thickness: ~3% flat plate or symmetric
  Location: trailing edge of fin root flush with aft end of boat tail

NOTES
  - The nose cone should taper smoothly from a point (or near-point)
    to the full body diameter.
  - The boat tail is a conical frustum reducing the base area.
  - Fins should be thin symmetric sections (NACA 0006 or flat plate).
  - Model does not need internal structure, motor, or payload bay detail.
===============================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/rocket_spec.txt
chmod 644 /home/ga/Desktop/rocket_spec.txt

# Remove any previous rocket model to ensure a clean state
rm -f "$MODELS_DIR/sounding_rocket.vsp3"
rm -f /tmp/openvsp_sounding_rocket_result.json

# Kill any running OpenVSP
kill_openvsp

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