#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_airship_envelope_sizing ==="

# Directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop

# Specification File
cat > /home/ga/Desktop/airship_spec.txt << 'EOF'
HAPS AIRSHIP GEOMETRY SPECIFICATION
===================================
Project: Stratospheric Heavy Lift

ENVELOPE (FUSELAGE) REQUIREMENTS:
- Target Displaced Volume: 75,000 m^3
- Fineness Ratio (Length / Max Diameter): 5.0
- Shape: Streamlined, axisymmetric body (circular cross-sections)

EMPENNAGE REQUIREMENTS:
- Minimum of 3 tail fins (Wing components)
- Positioned in the aft 20% of the envelope length

OUTPUT REQUIREMENTS:
- Save OpenVSP model to: ~/Documents/OpenVSP/haps_airship.vsp3
- Write a report to: ~/Desktop/airship_report.txt containing:
    1. Final Envelope Length (m)
    2. Final Max Diameter (m)
    3. Final Measured Volume (m^3)
EOF
chown ga:ga /home/ga/Desktop/airship_spec.txt

# Clear stale files
rm -f "$MODELS_DIR/haps_airship.vsp3"
rm -f /home/ga/Desktop/airship_report.txt
rm -f /tmp/openvsp_airship_result.json

# Kill existing VSP
kill_openvsp

# Start timestamp
date +%s > /tmp/task_start_timestamp

# Launch blank OpenVSP
launch_openvsp
WID=$(wait_for_openvsp 60)
if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="