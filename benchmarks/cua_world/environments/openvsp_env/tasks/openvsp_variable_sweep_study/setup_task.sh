#!/bin/bash
echo "=== Setting up openvsp_variable_sweep_study ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

kill_openvsp

# Create baseline model with a Python script using standard XML manipulation
# We'll strip eCRM down to its Wing and rename it to Main_Wing
python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import sys

base_file = "/workspace/data/eCRM-001_wing_tail.vsp3"
output_file = "/home/ga/Documents/OpenVSP/variable_sweep_base.vsp3"

try:
    tree = ET.parse(base_file)
    root = tree.getroot()
    vehicle = root.find('Vehicle')
    if vehicle is not None:
        for geom in vehicle.findall('Geom'):
            name = geom.find('Name')
            if name is not None and name.text == 'Wing':
                name.text = 'Main_Wing'
            else:
                vehicle.remove(geom)
    tree.write(output_file)
    print("Baseline model created successfully.")
except Exception as e:
    print(f"Error creating baseline: {e}", file=sys.stderr)
PYEOF

chown ga:ga "$MODELS_DIR/variable_sweep_base.vsp3"

# Write the schedule document
cat > /home/ga/Desktop/sweep_schedule.txt << 'EOF'
VARIABLE SWEEP GEOMETRY SCHEDULE
================================

1. Open the baseline model (/home/ga/Documents/OpenVSP/variable_sweep_base.vsp3).
2. The model contains a 'Main_Wing' component. Modify it so it has exactly TWO sections (delete any extra sections).
   - Section 1 (Inboard): Leave parameters as is (this is the fixed glove).
   - Section 2 (Outboard): This is the variable-sweep panel.

Generate two configurations:

1. TAKEOFF CONFIGURATION (Low Speed)
   - Outboard Panel (Section 2) LE Sweep: 20 deg
   - Outboard Panel (Section 2) Span: 7.5 m
   - Save as: ~/Documents/OpenVSP/vswing_takeoff.vsp3

2. DASH CONFIGURATION (High Speed)
   - Outboard Panel (Section 2) LE Sweep: 68 deg
   - Outboard Panel (Section 2) Span: 4.8 m
   - Save as: ~/Documents/OpenVSP/vswing_dash.vsp3

DELIVERABLE:
Run DegenGeom analysis (Analysis > Degen Geom) on BOTH configurations.
Find the 'Main_Wing' projected planform area in the generated CSV files.
Write these two area values clearly to ~/Desktop/sweep_area_report.txt.
EOF
chown ga:ga /home/ga/Desktop/sweep_schedule.txt

rm -f /tmp/task_result.json

# Launch OpenVSP with the baseline model
launch_openvsp "$MODELS_DIR/variable_sweep_base.vsp3"
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_initial.png
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear in time"
    take_screenshot /tmp/task_initial.png
fi

echo "=== Setup complete ==="