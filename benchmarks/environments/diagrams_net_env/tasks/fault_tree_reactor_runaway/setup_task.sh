#!/bin/bash
set -e

echo "=== Setting up Fault Tree Analysis Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Incident Investigation Report
cat > "/home/ga/Desktop/incident_investigation_report.txt" << 'EOF'
INCIDENT INVESTIGATION REPORT: REACTOR R-101 THERMAL RUNAWAY
Date: 2024-03-15 | Case ID: CSB-2024-05-TX
Status: DRAFT - PENDING FTA COMPLETION

INCIDENT SUMMARY:
On Feb 12, Reactor R-101 experienced an uncontrolled exothermic reaction leading to relief valve activation. The investigation team has identified the causal chain. You must map this to the Fault Tree.

TOP EVENT: Uncontrolled Exothermic Reaction

BRANCH 1: COOLING SYSTEM FAILURE (Subsystem Color: BLUE / #dae8fc)
This branch connects to the top event via the existing OR gate.
Analysis shows this failure requires BOTH of the following to occur (AND Logic):
  A. Coolant Flow Loss (Intermediate Event). Causes (OR Logic):
     1. Pump mechanical failure (Basic Event, P=2.1E-3)
     2. Coolant line blockage (Basic Event, P=8.5E-4)
     3. Power supply interruption (Basic Event, P=1.2E-3)
  B. Backup Cooling Unavailable (Intermediate Event). Causes (OR Logic):
     1. Backup pump in maintenance (Basic Event, P=4.0E-2)
     2. Backup valve stuck closed (Basic Event, P=3.5E-3)
     3. Operator fails to activate backup (Basic Event, P=1.5E-1)

BRANCH 2: REACTION CONTROL FAILURE (Subsystem Color: ORANGE / #ffe6cc)
This branch connects to the top event via the existing OR gate.
Causes (OR Logic - any single failure is sufficient):
  A. Incorrect Reagent Charge (Intermediate Event). Requires BOTH (AND Logic):
     1. Scale calibration drift (Basic Event, P=5.0E-3)
     2. Operator skips verification step (Basic Event, P=8.0E-2)
  B. Temperature Monitoring Failure (Intermediate Event). Causes (OR Logic):
     1. Thermocouple drift/failure (Basic Event, P=6.0E-3)
     2. DCS alarm suppressed (Basic Event, P=2.0E-2)
     3. Display unit malfunction (Basic Event, P=1.0E-3)
  C. Catalyst Degradation (Undeveloped Event / Diamond shape)

BRANCH 3: EMERGENCY SHUTDOWN (ESD) FAILURE (Subsystem Color: RED / #f8cecc)
This branch connects to the top event via the existing OR gate.
Analysis shows the ESD failed to arrest the runaway. This requires BOTH (AND Logic):
  A. Automated ESD Failure (Intermediate Event). Causes (OR Logic):
     1. SIS logic solver failure (Basic Event, P=1.0E-3)
     2. High-temperature sensor failed (Basic Event, P=4.0E-3)
     3. ESD valve fails to close (Basic Event, P=2.5E-3)
  B. Manual ESD Failure (Intermediate Event). Requires BOTH (AND Logic):
     1. Operator unaware of conditions (Basic Event, P=2.0E-1)
     2. ESD button not accessible (Basic Event, P=5.0E-2)

REQUIREMENTS:
- All Basic Events must be labeled with their probability (e.g., "P=2.1E-3").
- Use correct shapes: Rectangles for Intermediate, Circles for Basic, Diamond for Undeveloped.
- Color code the events based on the subsystem colors listed above.
EOF

# 3. Create FTA Notation Reference
cat > "/home/ga/Desktop/fta_notation_reference.txt" << 'EOF'
FAULT TREE ANALYSIS (FTA) SYMBOL REFERENCE (IEC 61025)

EVENTS:
[ Rectangle ] : Intermediate Event (Fault that is further developed)
[ Circle    ] : Basic Event (Primary failure, no further development, has probability)
[ Diamond   ] : Undeveloped Event (Fault not analyzed further due to lack of info)
[ House     ] : Normal Event (Expected event, not a fault)

GATES:
[ AND Gate ]  : Output occurs ONLY if ALL inputs occur. (Symbol: Rounded top, flat bottom)
[ OR Gate  ]  : Output occurs if ANY input occurs. (Symbol: Curved bottom and pointed top)

NOTES:
- Events flow UP the tree (Causes at bottom -> Effect at top).
- Probabilities are typically assigned only to Basic Events (Circles).
EOF

# 4. Create Partial .drawio File (Uncompressed XML for simplicity in bash)
# Contains Top Event + Main OR Gate + 3 Stub Branches
cat > "/home/ga/Diagrams/reactor_fta.drawio" << 'EOF'
<mxfile host="Electron" modified="2024-03-01T10:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.0.0 Chrome/120.0.6099.109 Electron/28.1.0 Safari/537.36" version="24.0.0" type="device">
  <diagram id="fta-1" name="Page-1">
    <mxGraphModel dx="1422" dy="868" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- Top Event -->
        <mxCell id="top_event" value="Uncontrolled Exothermic Reaction" style="html=1;whiteSpace=wrap;fillColor=#ffffff;strokeColor=#000000;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry x="360" y="40" width="160" height="60" as="geometry" />
        </mxCell>
        
        <!-- Top OR Gate -->
        <mxCell id="gate_1" value="" style="html=1;verticalLabelPosition=bottom;align=center;verticalAlign=top;shape=mxgraph.electrical.logic_gates.or;rotation=-90;" vertex="1" parent="1">
          <mxGeometry x="410" y="140" width="60" height="40" as="geometry" />
        </mxCell>
        
        <!-- Connection Top -> Gate -->
        <mxCell id="edge_1" value="" style="endArrow=none;html=1;rounded=0;entryX=0.5;entryY=1;entryDx=0;entryDy=0;exitX=1;exitY=0.5;exitDx=0;exitDy=0;exitPerimeter=0;" edge="1" parent="1" source="gate_1" target="top_event">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="440" y="140" as="sourcePoint" />
            <mxPoint x="440" y="100" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        
        <!-- Branch 1 Stub -->
        <mxCell id="stub_1" value="Cooling System Failure" style="html=1;whiteSpace=wrap;" vertex="1" parent="1">
          <mxGeometry x="160" y="240" width="140" height="60" as="geometry" />
        </mxCell>
        
        <!-- Branch 2 Stub -->
        <mxCell id="stub_2" value="Reaction Control Failure" style="html=1;whiteSpace=wrap;" vertex="1" parent="1">
          <mxGeometry x="370" y="240" width="140" height="60" as="geometry" />
        </mxCell>
        
        <!-- Branch 3 Stub -->
        <mxCell id="stub_3" value="Emergency Shutdown Failure" style="html=1;whiteSpace=wrap;" vertex="1" parent="1">
          <mxGeometry x="580" y="240" width="140" height="60" as="geometry" />
        </mxCell>
        
        <!-- Connections Gate -> Stubs -->
        <mxCell id="edge_2" style="endArrow=none;html=1;rounded=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;entryPerimeter=0;exitX=0.5;exitY=0;exitDx=0;exitDy=0;" edge="1" parent="1" source="stub_1" target="gate_1">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="edge_3" style="endArrow=none;html=1;rounded=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;entryPerimeter=0;exitX=0.5;exitY=0;exitDx=0;exitDy=0;" edge="1" parent="1" source="stub_2" target="gate_1">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="edge_4" style="endArrow=none;html=1;rounded=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;entryPerimeter=0;exitX=0.5;exitY=0;exitDx=0;exitDy=0;" edge="1" parent="1" source="stub_3" target="gate_1">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown ga:ga /home/ga/Diagrams/reactor_fta.drawio
chown ga:ga /home/ga/Desktop/incident_investigation_report.txt
chown ga:ga /home/ga/Desktop/fta_notation_reference.txt
chmod 644 /home/ga/Diagrams/reactor_fta.drawio

# 5. Launch draw.io
echo "Launching draw.io..."
if ! pgrep -f "drawio" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/reactor_fta.drawio &"
    sleep 5
fi

# 6. Window Management & Dialog Dismissal
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Aggressive update dialog dismissal
echo "Dismissing update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done
# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Record Initial State
# Count "vertex" elements in the XML (shapes)
INITIAL_SHAPES=$(grep -o 'vertex="1"' /home/ga/Diagrams/reactor_fta.drawio | wc -l)
echo "$INITIAL_SHAPES" > /tmp/initial_shape_count
date +%s > /tmp/task_start_time

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="