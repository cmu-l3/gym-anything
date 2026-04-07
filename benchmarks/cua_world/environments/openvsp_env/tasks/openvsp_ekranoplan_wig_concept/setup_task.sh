#!/bin/bash
echo "=== Setting up openvsp_ekranoplan_wig_concept ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# Ensure directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the WIG specification document
cat > /home/ga/Desktop/airfish_wig_spec.txt << 'SPEC_EOF'
WIG COASTAL FERRY - GEOMETRY SPECIFICATION
==========================================
Project: Coastal Ekranoplan Transport
Units: Metric (meters and degrees)

1. Fuselage
   - Length: ~17.0 m
   - Type: FuselageGeom or Pod

2. Main Wing
   - Span: 15.0 m (total)
   - Chord: 4.0 m
   - Ground Effect Endplates: Add an outboard wing section to the main wing. Set this section's Span to ~1.5 m and Dihedral to -90° (pointing straight down).

3. Vertical Tail (VTail)
   - Span/Height: 4.5 m
   - Symmetry: NONE (Must disable standard XZ planar symmetry flag so it is a single vertical fin, not a V-tail).
   - Position: Aft fuselage.

4. Horizontal Tail (HTail)
   - Type: T-Tail configuration.
   - Position: Mounted atop the VTail. Set its Z_Location (or Z_Rel_Location) to >= 3.5 m.

SAVE FINAL MODEL AS:
/home/ga/Documents/OpenVSP/wig_concept.vsp3
SPEC_EOF

chown ga:ga /home/ga/Desktop/airfish_wig_spec.txt
chmod 644 /home/ga/Desktop/airfish_wig_spec.txt

# Remove any previous task outputs
rm -f "$MODELS_DIR/wig_concept.vsp3"
rm -f /tmp/task_result.json

# Kill any running OpenVSP
kill_openvsp

# Launch blank OpenVSP
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