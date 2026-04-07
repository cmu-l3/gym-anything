#!/bin/bash
# Setup script for openvsp_suboff_cruciform_tail task
set -e

echo "=== Setting up openvsp_suboff_cruciform_tail ==="

source /workspace/scripts/task_utils.sh

# Ensure directories exist
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Kill any running OpenVSP instance
kill_openvsp

# 1. Generate the Baseline Model using OpenVSP's AngelScript API
# This ensures we have a perfectly valid Fuselage-only model as the starting point.
cat > /tmp/make_baseline.vspscript << 'EOF'
void main() {
    string vid = AddGeom("FUSELAGE");
    SetParmVal(vid, "Length", "Design", 8.0);
    SetParmVal(vid, "Diameter", "Design", 1.0);
    Update();
    WriteVSPFile("/home/ga/Documents/OpenVSP/SUBOFF_baseline.vsp3");
}
EOF

# Run OpenVSP in batch mode to execute the script
if [ -n "$OPENVSP_BIN" ]; then
    "$OPENVSP_BIN" -batch -script /tmp/make_baseline.vspscript > /dev/null 2>&1 || true
fi

# Fallback minimal XML if the script fails for any reason
if [ ! -f "$MODELS_DIR/SUBOFF_baseline.vsp3" ]; then
    echo "Creating fallback baseline model..."
    cat > "$MODELS_DIR/SUBOFF_baseline.vsp3" << 'EOF'
<?xml version="1.0"?>
<VSP_NO_GUI_Doc Version="3">
  <Vehicle>
    <FuselageGeom>
      <ParmContainer>
        <ID>BASE_HULL</ID>
        <Name>Fuselage</Name>
        <Parm Name="Length" Value="8.0"/>
      </ParmContainer>
    </FuselageGeom>
  </Vehicle>
</VSP_NO_GUI_Doc>
EOF
fi

chmod 644 "$MODELS_DIR/SUBOFF_baseline.vsp3"
chown ga:ga "$MODELS_DIR/SUBOFF_baseline.vsp3"

# 2. Write the specification document
cat > /home/ga/Desktop/suboff_tail_spec.txt << 'SPEC_EOF'
DARPA SUBOFF Appendage Specification
====================================
Configuration: 4-fin Cruciform Aft Control Surfaces

Geometry:
- Component Type: Wing
- X-Location (Origin): 4.0 m
- Total Span: 1.2 m
- Root Chord: 0.4 m
- Tip Chord: 0.2 m

Symmetry Settings (Sym Tab):
- Default Planar (XZ) Symmetry: OFF
- Rotational (Axial) Symmetry: ON
- Number of Rotational Copies: 4

Output:
Save completed model as: /home/ga/Documents/OpenVSP/SUBOFF_cruciform.vsp3
SPEC_EOF

chmod 644 /home/ga/Desktop/suboff_tail_spec.txt
chown ga:ga /home/ga/Desktop/suboff_tail_spec.txt

# 3. Clean up any stale files from previous runs
rm -f "$MODELS_DIR/SUBOFF_cruciform.vsp3"
rm -f /tmp/openvsp_suboff_tail_result.json

# 4. Record task start timestamp (Anti-gaming)
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# 5. Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/SUBOFF_baseline.vsp3"

# Wait for window and configure state
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    # Take initial screenshot for evidence
    take_screenshot /tmp/task_start_screenshot.png ga
    echo "OpenVSP launched successfully with baseline model."
else
    echo "WARNING: OpenVSP window did not appear."
    take_screenshot /tmp/task_start_screenshot.png ga
fi

echo "=== Setup complete ==="