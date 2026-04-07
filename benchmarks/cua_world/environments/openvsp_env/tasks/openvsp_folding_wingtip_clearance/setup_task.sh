#!/bin/bash
echo "=== Setting up openvsp_folding_wingtip_clearance task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write engineering specification memo
cat > /home/ga/Desktop/wingtip_fold_spec.txt << 'SPEC_EOF'
============================================================
  GATE CLEARANCE STUDY - FOLDING WINGTIP SPECIFICATION
============================================================
Context:
The eCRM-001 baseline wingspan exceeds ICAO Code D limits (52m).
We need to evaluate a folding wingtip mechanism.

Instructions:
1. Open the baseline model: ~/Documents/OpenVSP/eCRM-001_wing_tail.vsp3
2. Select the main 'Wing' component.
3. In the Section tab, locate the outermost spanwise panel.
4. SPLIT this outermost panel into two sections to preserve the local planform.
5. Set the Dihedral angle of the newly created outermost section to 90.0 degrees.
6. Save the modified model as: ~/Documents/OpenVSP/eCRM_folded.vsp3
7. Measure the new total projected wingspan (tip-to-tip).
8. Write the new wingspan value to: ~/Desktop/gate_span_report.txt
============================================================
SPEC_EOF

chown ga:ga /home/ga/Desktop/wingtip_fold_spec.txt
chmod 644 /home/ga/Desktop/wingtip_fold_spec.txt

# Copy baseline model to working location
cp /workspace/data/eCRM-001_wing_tail.vsp3 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"
chmod 644 "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Clean any stale outputs from prior runs
rm -f "$MODELS_DIR/eCRM_folded.vsp3"
rm -f /home/ga/Desktop/gate_span_report.txt
rm -f /tmp/openvsp_folding_wingtip_clearance_result.json

# Launch OpenVSP with the baseline model
kill_openvsp
launch_openvsp "$MODELS_DIR/eCRM-001_wing_tail.vsp3"

# Wait for application, focus and maximize it
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="