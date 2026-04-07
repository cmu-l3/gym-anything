#!/bin/bash
echo "=== Setting up openvsp_canard_pusher_config ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# Ensure directories exist
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Documents/OpenVSP
chown -R ga:ga /home/ga/Desktop /home/ga/Documents

# Write the aircraft specification to the Desktop
cat > /home/ga/Desktop/canard_pusher_spec.txt << 'EOF'
=== CANARD PUSHER AIRCRAFT SPECIFICATION ===
Configuration: Canard pusher (NO conventional horizontal tail)
Reference: Rutan VariEze general arrangement

FUSELAGE
  Length:         4.30 m
  Max Width:      1.10 m
  Max Height:     1.20 m

MAIN WING (aft-mounted, mid/low position)
  Total Span:     6.75 m
  Root Chord:     1.55 m
  Tip Chord:      0.65 m
  LE Sweep:       26.0°
  Dihedral:       -3.0° (slight anhedral)
  X-Origin:       2.40 m aft of nose (relative to fuselage nose)
  Airfoil:        Use default symmetric or NACA 4-digit

CANARD (forward wing, high-mounted)
  Total Span:     3.05 m
  Root Chord:     0.70 m
  Tip Chord:      0.40 m
  LE Sweep:       14.0°
  X-Origin:       0.30 m aft of nose (MUST be forward of main wing)

WINGLETS (replace conventional vertical tail)
  Height:         0.70 m each
  Root Chord:     0.80 m
  Mounted at main wing tips

VERTICAL FIN (small dorsal fin on fuselage, optional)
  Height:         0.40 m
  Root Chord:     0.60 m

NOTES:
- The canard MUST be positioned forward of the main wing
- There is NO conventional horizontal tail behind the wing
- The engine is a pusher mounted behind the cockpit
- Save as: /home/ga/Documents/OpenVSP/canard_pusher.vsp3
EOF

chmod 644 /home/ga/Desktop/canard_pusher_spec.txt

# Remove any old vsp3 files to ensure a clean slate
rm -f /home/ga/Documents/OpenVSP/canard_pusher.vsp3
rm -f /tmp/canard_pusher_result.json

# Kill any existing OpenVSP instances
kill_openvsp

# Start OpenVSP blank
echo "Launching OpenVSP..."
launch_openvsp
WID=$(wait_for_openvsp 60)

if [ -n "$WID" ]; then
    focus_openvsp
    sleep 2
    echo "OpenVSP launched successfully."
else
    echo "WARNING: OpenVSP did not appear — agent may need to launch it manually."
fi

# Take initial screenshot showing blank OpenVSP and the spec file on desktop
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="