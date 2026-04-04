#!/bin/bash
set -e

echo "=== Setting up HVAC AHU Control Schematic Task ==="

# 1. Create the Sequence of Operations text file
# This contains the "specs" the agent must implement
cat > /home/ga/Desktop/AHU_Sequence_of_Operations.txt << 'EOF'
PROJECT: GENERAL HOSPITAL SURGICAL WING RETROFIT
SYSTEM: AHU-1 (Air Handling Unit 1)
TYPE: Single Duct Variable Air Volume (VAV) with Economizer

DESCRIPTION:
AHU-1 is a draw-through air handling unit serving the surgical suite. The unit consists of the following components arranged in the direction of airflow:

1. MIXING SECTION:
   - Outdoor Air Damper (OAD-1)
   - Return Air Damper (RAD-1)
   - Mixing Box where air streams merge

2. FILTRATION:
   - MERV-8 Pre-Filter (PF-1)
   - MERV-14 Final Filter (FF-1)

3. HEATING SECTION:
   - Hot Water Heating Coil (HC-1)
   - Controlled by 2-way Heating Valve (HV-1)

4. COOLING SECTION:
   - Chilled Water Cooling Coil (CC-1)
   - Controlled by 2-way Cooling Valve (CV-1)

5. SUPPLY FAN SECTION:
   - Supply Fan (SF-1)
   - Driven by Variable Frequency Drive (VFD-1)

SENSORS & CONTROL POINTS:
- MAT (Mixed Air Temperature): Located in mixing box, before filters.
- SAT (Supply Air Temperature): Located in discharge duct, after fan.
- RAT (Return Air Temperature): Located in return duct before mixing box.
- DSP (Duct Static Pressure): Located 2/3 down the supply duct.
- FST (Freeze Stat): Located on face of Heating Coil.

CONTROL LOGIC CONNECTIONS (To be drawn as DASHED lines):
- SAT sensor connects to Heating Valve (HV-1) and Cooling Valve (CV-1) controllers to maintain discharge temperature.
- DSP sensor connects to Supply Fan VFD (VFD-1) to maintain duct static pressure.
- MAT sensor connects to Dampers (OAD-1/RAD-1) for economizer control.

INSTRUCTIONS:
Create a control diagram showing the airflow path (left to right) and control connections. 
Use SOLID lines for air/water flow and DASHED lines for control signals.
Label all components with their tags (e.g., SF-1, CC-1).
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/AHU_Sequence_of_Operations.txt
chmod 644 /home/ga/Desktop/AHU_Sequence_of_Operations.txt

# 2. Clean up previous run artifacts
rm -f /home/ga/Diagrams/AHU-1_Schematic.drawio
rm -f /home/ga/Diagrams/AHU-1_Schematic.pdf
mkdir -p /home/ga/Diagrams
chown ga:ga /home/ga/Diagrams

# 3. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch draw.io (clean state)
echo "Launching draw.io..."
# We use the env's utility or launch directly. 
# Using a background process with logging.
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /tmp/drawio.log 2>&1 &"

# 5. Handle the "Update Available" dialog annoyance
# This dialog often blocks the "Create New Diagram" screen.
echo "Waiting for draw.io to launch..."
sleep 5
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "draw.io window detected."
        
        # Aggressively try to dismiss update dialogs
        # Try Escape (Cancel)
        DISPLAY=:1 xdotool key Escape 2>/dev/null
        sleep 0.5
        # Try it again just in case
        DISPLAY=:1 xdotool key Escape 2>/dev/null
        break
    fi
    sleep 1
done

# 6. Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="