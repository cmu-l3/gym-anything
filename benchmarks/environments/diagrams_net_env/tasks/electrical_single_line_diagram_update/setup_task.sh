#!/bin/bash
set -e

echo "=== Setting up Electrical SLD Update Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Engineering Memo
cat > /home/ga/Desktop/project_memo_ev_expansion.txt << 'EOF'
PROJECT MEMORANDUM
------------------
To: Electrical Design Team
From: J. Smith, PE
Date: Oct 24, 2025
Subject: Building 4 EV Charger Expansion - SLD Update

We need to update the As-Built Single Line Diagram for Building 4 to include the new electric vehicle charging infrastructure.

Please modify the "Main Switchboard (MSB)" diagram to add:

1. NEW DISTRIBUTION PANEL
   - Tag: DP-EV
   - Rating: 225A MLO (Main Lugs Only)
   - Voltage: 480/277V, 3-Phase, 4-Wire

2. NEW FEEDER CIRCUIT
   - Source: New breaker in Main Switchboard (MSB)
   - Breaker Rating: 200A / 3-Pole
   - Feeder Schedule: 3#3/0 AWG Cu + 1#6 AWG GND in 2" EMT

Please ensure all wire sizes and conduit types are clearly labeled on the feeder line.
Export the updated drawing to PDF for the permit application package.
EOF

# 3. Create the Initial .drawio file (Uncompressed XML)
cat > /home/ga/Diagrams/building_4_sld.drawio << 'EOF'
<mxfile host="Electron" modified="2025-10-23T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.7.5 Chrome/128.0.6613.119 Electron/32.0.1 Safari/537.36" version="24.7.5" type="device">
  <diagram id="SLD-Build4" name="Page-1">
    <mxGraphModel dx="1422" dy="768" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="2" value="Utility Transformer&#xa;1000kVA 12.47kV/480V" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="320" y="40" width="160" height="60" as="geometry" />
        </mxCell>
        <mxCell id="3" value="" style="endArrow=none;html=1;entryX=0.5;entryY=0;entryDx=0;entryDy=0;exitX=0.5;exitY=1;exitDx=0;exitDy=0;" edge="1" parent="1" source="2" target="4">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>
        <mxCell id="4" value="Main Switchboard (MSB)&#xa;1200A 480/277V 3Ph 4W" style="rounded=0;whiteSpace=wrap;html=1;align=left;verticalAlign=top;spacingLeft=10;" vertex="1" parent="1">
          <mxGeometry x="160" y="160" width="480" height="200" as="geometry" />
        </mxCell>
        <mxCell id="5" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="180" y="200" width="440" height="10" as="geometry" />
        </mxCell>
        <mxCell id="6" value="400A" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="200" y="210" width="40" height="40" as="geometry" />
        </mxCell>
        <mxCell id="7" value="200A" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="300" y="210" width="40" height="40" as="geometry" />
        </mxCell>
        <mxCell id="8" value="100A" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="400" y="210" width="40" height="40" as="geometry" />
        </mxCell>
        <mxCell id="9" value="Panel L1&#xa;(Lighting)" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="180" y="440" width="80" height="60" as="geometry" />
        </mxCell>
        <mxCell id="10" value="" style="endArrow=none;html=1;entryX=0.5;entryY=0;entryDx=0;entryDy=0;exitX=0.5;exitY=1;exitDx=0;exitDy=0;" edge="1" parent="1" source="6" target="9">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>
        <mxCell id="11" value="Panel H1&#xa;(HVAC)" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="280" y="440" width="80" height="60" as="geometry" />
        </mxCell>
        <mxCell id="12" value="" style="endArrow=none;html=1;entryX=0.5;entryY=0;entryDx=0;entryDy=0;exitX=0.5;exitY=1;exitDx=0;exitDy=0;" edge="1" parent="1" source="7" target="11">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
grep -c "mxCell" /home/ga/Diagrams/building_4_sld.drawio > /tmp/initial_cell_count.txt

# 5. Launch Application
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/building_4_sld.drawio > /dev/null 2>&1 &"

# 6. Wait for Window and Dismiss Dialogs
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Aggressive dialog dismissal (Update/Confirm)
echo "Dismissing dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true # Try to hit Cancel if focused
    sleep 0.5
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="