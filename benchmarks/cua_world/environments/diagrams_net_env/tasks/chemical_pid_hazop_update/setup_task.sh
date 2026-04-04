#!/bin/bash
set -e

echo "=== Setting up Chemical P&ID HazOp Update Task ==="

# Ensure directories exist
mkdir -p /home/ga/Diagrams /home/ga/Desktop

# 1. Create the HazOp Recommendations Text File
cat > /home/ga/Desktop/hazop_recommendations.txt << 'EOF'
HAZOP STUDY REPORT: METHANOL STORAGE UNIT
DATE: 2024-05-12
STATUS: ACTION REQUIRED

The following safety and operability gaps were identified for Tank T-100. Please update the P&ID diagram immediately.

ITEM 1: OVERPRESSURE PROTECTION
Description: Tank T-100 lacks overpressure protection.
Action: Install a Pressure Relief Valve (PSV) on the tank vapor space.
Tag: PSV-101

ITEM 2: TRANSFER PUMP
Description: Gravity drain is insufficient for new process requirements.
Action: Install a Centrifugal Pump on the tank bottom outlet line.
Tag: P-101

ITEM 3: BACKFLOW PREVENTION
Description: Potential for high-pressure backflow from downstream process.
Action: Install a Check Valve immediately on the pump discharge.
Tag: V-102

ITEM 4: TEMPERATURE CONTROL
Description: Process fluid requires cooling before entering the reactor header.
Action: Install a Shell and Tube Heat Exchanger downstream of the check valve.
Tag: E-101

INSTRUCTIONS:
- Use standard P&ID symbols (Process Engineering library).
- Ensure flow path is connected: Tank -> Pump -> Valve -> Exchanger -> To Process.
- Label all new equipment with tags.
- Export result as PDF to ~/Diagrams/methanol_storage_rev1.pdf
EOF

# 2. Create the Starter Diagram (XML)
# Contains just the Tank T-100 and a basic inlet line
cat > /home/ga/Diagrams/methanol_storage.drawio << 'EOF'
<mxfile host="Electron" modified="2024-05-12T10:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.0.0 Chrome/120.0.6099.109 Electron/28.1.0 Safari/537.36" etag="starting_state" version="24.0.0" type="device">
  <diagram id="pid_diagram" name="Page-1">
    <mxGraphModel dx="1422" dy="868" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="tank_1" value="Methanol Storage&#xa;T-100" style="verticalLabelPosition=bottom;verticalAlign=top;html=1;shape=mxgraph.pid.vessels.tank;pointerEvents=1;align=center;whiteSpace=wrap;" vertex="1" parent="1">
          <mxGeometry x="200" y="200" width="100" height="150" as="geometry" />
        </mxCell>
        <mxCell id="inlet_1" value="From Tanker" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;" vertex="1" parent="1">
          <mxGeometry x="40" y="210" width="80" height="30" as="geometry" />
        </mxCell>
        <mxCell id="line_1" value="" style="endArrow=classic;html=1;rounded=0;entryX=0;entryY=0.25;entryDx=0;entryDy=0;entryPerimeter=0;" edge="1" parent="1" target="tank_1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="120" y="238" as="sourcePoint" />
            <mxPoint x="170" y="190" as="targetPoint" />
          </mxGeometry>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/hazop_recommendations.txt
chown ga:ga /home/ga/Diagrams/methanol_storage.drawio

# 3. Cleanup Previous Runs
rm -f /home/ga/Diagrams/methanol_storage_rev1.pdf
rm -f /tmp/task_start_time.txt

# 4. Record Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/methanol_storage.drawio > /dev/null 2>&1 &"

# 6. Wait for Window and Dismiss Dialogs
echo "Waiting for application window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Aggressive dialog dismissal (Update dialogs are common)
sleep 5
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done
# In case it needs a click (sometimes Escape doesn't work on modal)
# Try clicking the "Cancel" area relative to a typical centered dialog
DISPLAY=:1 xdotool mousemove 1050 600 click 1 2>/dev/null || true

# Maximize Window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="