#!/bin/bash
# Setup script for openvsp_inverted_gull_wing task

set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_inverted_gull_wing task ==="

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the inverted gull wing specification document
cat > /home/ga/Desktop/gull_wing_spec.txt << 'SPEC_EOF'
============================================================
  INVERTED GULL WING - GEOMETRY SPECIFICATION
  Document: GW-400-WING-001
  Units: Metric (meters and degrees)
============================================================

Overview:
Create a multi-panel wing with an inboard anhedral section
and an outboard dihedral section (inverted gull wing).

Inboard Panel (Root to Knee):
-----------------------------
Span           :  2.5 m
Root Chord     :  2.2 m
Tip Chord      :  2.2 m
Dihedral       : -15.0 degrees (Anhedral)

Outboard Panel (Knee to Tip):
-----------------------------
Span           :  3.8 m
Tip Chord      :  1.2 m
Dihedral       :  +8.5 degrees

Component Requirements:
-----------------------
1. Start with a new Wing component.
2. Insert a new spanwise section so the wing has two distinct panels.
3. Apply the parameters above to the respective sections.
4. Save the completed model as:
   /home/ga/Documents/OpenVSP/inverted_gull_wing.vsp3
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/gull_wing_spec.txt
chmod 644 /home/ga/Desktop/gull_wing_spec.txt

# Remove any previous model and result files
rm -f "$MODELS_DIR/inverted_gull_wing.vsp3"
rm -f /tmp/task_result.json

# Kill any running OpenVSP
kill_openvsp

# Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP (no file argument)
launch_openvsp
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