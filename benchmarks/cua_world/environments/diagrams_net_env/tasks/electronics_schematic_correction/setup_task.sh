#!/bin/bash
set -e

echo "=== Setting up Electronics Schematic Correction Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Requirement Spec File
cat > /home/ga/Desktop/lab_circuit_spec.txt << 'EOF'
LAB 3: 555 ASTABLE MULTIVIBRATOR SPECIFICATION
================================================

Target Frequency: ~1 Hz
Duty Cycle: ~50%

COMPONENT LIST:
----------------
U1: NE555 Timer IC
R1: 1kΩ (connected VCC -> Pin 7)
R2: 10kΩ (connected Pin 7 -> Pin 6/2)
C1: 10µF Electrolytic Capacitor (Pin 6/2 -> GND)
C2: 10nF Ceramic Capacitor (Pin 5 -> GND) - Noise filtering
R3: 470Ω (Output Current Limiter)
D1: LED (Red)

WIRING REQUIREMENTS:
--------------------
Pin 1: Ground
Pin 2: Trigger (Connect to Pin 6)
Pin 3: Output (Connect to R3 -> LED -> GND)
Pin 4: Reset (Connect to VCC to prevent reset)
Pin 5: Control Voltage (Connect to C2 -> GND)
Pin 6: Threshold (Connect to Pin 2)
Pin 7: Discharge (Between R1 and R2)
Pin 8: VCC (+5V to +15V)

ERRORS IN CURRENT DRAFT:
- R1/R2 values are swapped/incorrect.
- Missing timing capacitor C1.
- Missing control capacitor C2.
- Missing output stage (LED + Resistor).
- Pin 4 is floating (must be tied High/VCC).
- Pin 2 and 6 connection might be missing.
EOF

# 3. Create the "Broken" Draft Diagram
# This is a base64 encoded draw.io XML file containing:
# - 555 Timer IC
# - R1 (100k - WRONG)
# - R2 (1k - WRONG)
# - VCC and Ground symbols
# - Partial wiring
# We create it dynamically to ensure a clean state.

cat > /home/ga/Diagrams/555_timer_draft.drawio << 'EOF'
<mxfile host="Electron" modified="2023-10-27T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" etag="123" version="21.6.8" type="device">
  <diagram name="Page-1" id="page1">
    <mxGraphModel dx="1422" dy="868" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- 555 Timer IC -->
        <mxCell id="ic1" value="555 Timer" style="verticalLabelPosition=bottom;shadow=0;dashed=0;align=center;html=1;verticalAlign=top;shape=mxgraph.electrical.integrated_circuits.555_timer_2;" vertex="1" parent="1">
          <mxGeometry x="360" y="280" width="80" height="100" as="geometry" />
        </mxCell>
        <!-- VCC -->
        <mxCell id="vcc" value="VCC" style="verticalLabelPosition=bottom;shadow=0;dashed=0;align=center;html=1;verticalAlign=top;shape=mxgraph.electrical.signal_sources.vcc2;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="380" y="120" width="40" height="20" as="geometry" />
        </mxCell>
        <!-- GND -->
        <mxCell id="gnd" value="GND" style="verticalLabelPosition=bottom;shadow=0;dashed=0;align=center;html=1;verticalAlign=top;shape=mxgraph.electrical.signal_sources.ground_2;fontSize=10;" vertex="1" parent="1">
          <mxGeometry x="380" y="480" width="40" height="20" as="geometry" />
        </mxCell>
        <!-- R1 (Wrong Value 100k) -->
        <mxCell id="r1" value="R1&#xa;100k" style="verticalLabelPosition=bottom;shadow=0;dashed=0;align=center;html=1;verticalAlign=top;shape=mxgraph.electrical.resistors.resistor_2;rotation=90;" vertex="1" parent="1">
          <mxGeometry x="350" y="180" width="100" height="20" as="geometry" />
        </mxCell>
        <!-- R2 (Wrong Value 1k) -->
        <mxCell id="r2" value="R2&#xa;1k" style="verticalLabelPosition=bottom;shadow=0;dashed=0;align=center;html=1;verticalAlign=top;shape=mxgraph.electrical.resistors.resistor_2;rotation=90;" vertex="1" parent="1">
          <mxGeometry x="350" y="240" width="100" height="20" as="geometry" />
        </mxCell>
        <!-- Pin 8 to VCC -->
        <mxCell id="w1" value="" style="endArrow=none;html=1;rounded=0;entryX=0.5;entryY=1;entryDx=0;entryDy=0;entryPerimeter=0;" edge="1" parent="1" source="ic1" target="vcc">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="400" y="280" as="sourcePoint" />
            <mxPoint x="400" y="150" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Pin 1 to GND -->
        <mxCell id="w2" value="" style="endArrow=none;html=1;rounded=0;exitX=0.5;exitY=0;exitDx=0;exitDy=0;exitPerimeter=0;" edge="1" parent="1" source="gnd" target="ic1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="400" y="470" as="sourcePoint" />
            <mxPoint x="400" y="380" as="targetPoint" />
          </mxGeometry>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

chown ga:ga /home/ga/Diagrams/555_timer_draft.drawio
chown ga:ga /home/ga/Desktop/lab_circuit_spec.txt

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Diagrams/555_timer_draft.drawio > /tmp/initial_file_mtime.txt

# 5. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/555_timer_draft.drawio > /tmp/drawio.log 2>&1 &"

# 6. Handle Update Dialog (Crucial for automation)
sleep 5
# Attempt to dismiss update dialog if it appears
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -l | grep -i "update"; then
        DISPLAY=:1 xdotool key Escape
    fi
    # Also try generic escape just in case
    DISPLAY=:1 xdotool key Escape
    sleep 1
done

# 7. Maximize Window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="