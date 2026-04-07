#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up openvsp_tandem_wing_uav ==="

# Ensure working directories
mkdir -p "$MODELS_DIR"
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop 2>/dev/null || true

# Write the configuration spec to the desktop
cat > /home/ga/Desktop/tandem_uav_spec.txt << 'EOF'
==============================================
  Solar Tandem-Wing UAV - Geometry Specification
  Project: SunStrider T-200
  Author: Dr. A. Rutan, Chief Aerodynamicist
  Date: 2024-11-15
  Units: Meters
==============================================

FUSELAGE
  Length:            4.0 m
  Max Diameter:      0.50 m
  Shape:             Cylindrical mid-section with tapered nose/tail
  Nose at origin (X=0)

FORWARD WING (Canard-like lifting surface)
  Total Span:        6.0 m
  Root Chord:        0.80 m
  Tip Chord:         0.60 m
  X-Location:        0.8 m aft of nose (at root LE)
  Z-Location:        0.10 m above fuselage centerline
  Dihedral:          2.0 deg
  LE Sweep:          0.0 deg
  Incidence:         2.0 deg

AFT WING (Primary lifting surface)
  Total Span:        8.0 m
  Root Chord:        1.00 m
  Tip Chord:         0.70 m
  X-Location:        2.8 m aft of nose (at root LE)
  Z-Location:        0.15 m above fuselage centerline
  Dihedral:          3.0 deg
  LE Sweep:          0.0 deg
  Incidence:         0.0 deg

VERTICAL TAIL
  Span (height):     0.80 m
  Root Chord:        0.60 m
  Tip Chord:         0.35 m
  X-Location:        3.5 m aft of nose
  Mounted atop aft fuselage

NOTES:
  - Model name: tandem_wing_uav
  - Save to: /home/ga/Documents/OpenVSP/tandem_wing_uav.vsp3
  - All components should be named descriptively 
    (e.g., "ForwardWing", "AftWing", "Fuselage", "VerticalTail")
EOF

chmod 644 /home/ga/Desktop/tandem_uav_spec.txt
chown ga:ga /home/ga/Desktop/tandem_uav_spec.txt

# Clear any previous model that might exist
rm -f "$MODELS_DIR/tandem_wing_uav.vsp3"
rm -f /tmp/openvsp_tandem_wing_uav_result.json

# Kill any existing OpenVSP instance
kill_openvsp

# Capture task start time for anti-gaming verification
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
    echo "WARNING: OpenVSP did not appear - agent may need to launch it"
    take_screenshot /tmp/task_start_screenshot.png
fi

echo "=== Setup complete ==="