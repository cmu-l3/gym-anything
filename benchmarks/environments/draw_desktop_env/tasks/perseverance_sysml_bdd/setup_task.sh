#!/bin/bash
set -euo pipefail

echo "=== Setting up Perseverance SysML BDD Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specification file
cat > /home/ga/Desktop/perseverance_specs.txt << 'EOF'
MARS PERSEVERANCE ROVER - SYSTEM ARCHITECTURE SPECIFICATION
===========================================================

SYSTEM: Mars Perseverance Rover (Stereotype: <<System>>)

1. SUBSYSTEM: Power System
   - Component: MMRTG (Multi-Mission Radioisotope Thermoelectric Generator)
     * Property: Mass = 45 kg
     * Property: Power = 110 Watts

2. SUBSYSTEM: Mobility System
   - Component: Aluminum Wheels
     * Quantity: 6
     * Diameter: 52.5 cm
   - Component: Rocker-Bogie Suspension
     * Type: Passive Pivot

3. SUBSYSTEM: Science Instruments
   - Component: SuperCam
     * Location: Mast Head
   - Component: MOXIE (Mars Oxygen In-Situ Resource Utilization Experiment)
     * Location: Body internal
   - Component: MEDA (Mars Environmental Dynamics Analyzer)
     * Location: Deck/Mast

4. SUBSYSTEM: Robotic Arm
   - Component: Turret
     * Holds: SHERLOC, PIXL
   - Component: SHERLOC
     * Function: Fine-scale mineralogy
   - Component: PIXL
     * Function: X-ray spectrometer

INSTRUCTIONS FOR DIAGRAM:
- Use SysML Block Definition Diagram (BDD) notation.
- Hierarchy should be modeled using Composition (Black Diamond).
- Include multiplicity for the Wheels (6).
- Include "Mass" values in the block text where specified.
EOF

chown ga:ga /home/ga/Desktop/perseverance_specs.txt
echo "Created specification file at ~/Desktop/perseverance_specs.txt"

# Clean up previous runs
rm -f /home/ga/Desktop/perseverance_bdd.drawio
rm -f /home/ga/Desktop/perseverance_bdd.png

# Launch draw.io
# We use the standard launcher but ensure it's backgrounded and we wait for the window
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true /usr/bin/drawio --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window to appear
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss the "Open / Create New" dialog by pressing Escape
# This drops the user into a blank diagram
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="