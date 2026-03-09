#!/bin/bash
set -e

echo "=== Setting up Hydraulic Circuit Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 2. Create Work Order File
cat > /home/ga/Desktop/work_order_5592.txt << 'EOF'
WORK ORDER #5592
CUSTOMER: Heavy Digging Inc.
JOB: Install Auxiliary Thumb Circuit on CAT320

TECHNICAL SPECIFICATIONS:
Please create a hydraulic schematic for the certification file.

CIRCUIT REQUIREMENTS:
1. SOURCE: Variable Displacement Hydraulic Pump (Label: P1)
   - Connects to main pressure line.

2. RESERVOIR: Hydraulic Tank (Label: T1)
   - Common return point.

3. CONTROL: 4-Way, 3-Position (4/3) Directional Control Valve (Label: CV-1)
   - Solenoid operated
   - Spring centered
   - Closed center
   - Must show external drain line (dashed) to tank.

4. ACTUATOR: Double-Acting Cylinder (Label: CYL-1)
   - 4" Bore, 24" Stroke
   - Connect A/B ports to Control Valve.

5. PROTECTION/FILTRATION:
   - Main Relief Valve (RV-1) set to 3000 PSI just after pump.
   - Return Filter (F-1) on line back to tank.

DRAWING STANDARDS:
- Use ISO 1219 Symbols (Fluid Power Library).
- Solid lines for working flow.
- Dashed lines for pilot/drain.
EOF
chown ga:ga /home/ga/Desktop/work_order_5592.txt

# 3. Create Symbol Reference (Text based simulation of a cheat sheet)
cat > /home/ga/Desktop/iso_1219_reference.txt << 'EOF'
ISO 1219 SYMBOL REFERENCE GUIDE

PUMP: Circle with a filled triangle pointing OUT (Energy Source).
MOTOR: Circle with a filled triangle pointing IN.
TANK: Open container symbol (looks like a U).
CYLINDER (Double Acting): Rectangle with a T-bar (piston) inside, two ports.
VALVE (4/3): Three squares side-by-side. Arrows inside showing flow paths.
FILTER: Diamond shape with a dashed line down the center.
RELIEF VALVE: Square with an arrow offset from the line, normally closed.

LINE TYPES:
___________  (Solid) = Working Line (Pressure/Return)
-----------  (Dashed) = Pilot / Drain Line
-.-.-.-.-.-  (Phantom) = Enclosure / Assembly
EOF
chown ga:ga /home/ga/Desktop/iso_1219_reference.txt

# 4. Clean up previous artifacts
rm -f /home/ga/Diagrams/excavator_thumb_circuit.drawio
rm -f /home/ga/Diagrams/excavator_thumb_circuit.pdf

# 5. Record Start Time
date +%s > /tmp/task_start_time.txt

# 6. Launch draw.io
echo "Launching draw.io..."
export DISPLAY=:1
su - ga -c "/opt/drawio/drawio.AppImage --no-sandbox &" > /dev/null 2>&1

# 7. Wait for window and dismiss update dialogs
sleep 5
echo "Dismissing update dialogs..."
for i in {1..10}; do
    if wmctrl -l | grep -qi "update\|confirm"; then
        xdotool key Escape
        sleep 0.5
    fi
done
# Press escape a few more times just in case
xdotool key Escape
sleep 0.5
xdotool key Escape

# 8. Maximize window
if wmctrl -l | grep -qi "draw.io"; then
    wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz
fi

# 9. Initial Screenshot
scrot /tmp/task_initial.png

echo "=== Setup Complete ==="