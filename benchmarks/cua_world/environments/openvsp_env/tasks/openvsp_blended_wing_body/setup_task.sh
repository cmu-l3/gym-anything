#!/bin/bash
# Setup script for openvsp_blended_wing_body task
# Creates BWB spec document on Desktop, clears old outputs, launches blank OpenVSP

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_blended_wing_body ==="

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the BWB specification document (based on NASA X-48C subscale research vehicle)
cat > /home/ga/Desktop/bwb_spec.txt << 'SPEC_EOF'
==============================================
BWB Concept Aircraft - Geometry Specification
==============================================
Reference: Subscale BWB research vehicle (Metric)

OVERALL DIMENSIONS
  Total Wingspan         : 6.10 m
  Overall Length         : 3.80 m

CENTER BODY (inboard wing section)
  Root Chord            : 3.60 m
  Outboard Chord        : 2.50 m
  Leading-Edge Sweep    : 50 degrees
  Thickness-to-Chord    : ~17% (thick airfoil)

OUTER WING (outboard wing section)
  Root Chord            : 2.50 m  (matches center-body outboard edge)
  Tip Chord             : 0.60 m
  Leading-Edge Sweep    : 35 degrees
  Dihedral              : 3 degrees
  Twist (washout)       : -3 degrees at tip

VERTICAL FINS (twin fins, symmetric)
  Type                  : Two vertical fins
  Span (height)         : 0.70 m
  Root Chord            : 0.90 m
  Tip Chord             : 0.50 m
  Orientation           : Vertical (perpendicular to wing)

NOTES
  - The vehicle has NO conventional fuselage or horizontal tail.
  - Model symmetry: Use XZ symmetry for the main wing.
  - Save final model exactly as: /home/ga/Documents/OpenVSP/bwb_concept.vsp3
==============================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/bwb_spec.txt
chmod 644 /home/ga/Desktop/bwb_spec.txt

# Remove any previous concept model
rm -f "$MODELS_DIR/bwb_concept.vsp3"
rm -f /tmp/bwb_task_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp for anti-gaming (file must be created AFTER this)
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP (no file argument)
launch_openvsp
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

echo "=== Setup complete ==="