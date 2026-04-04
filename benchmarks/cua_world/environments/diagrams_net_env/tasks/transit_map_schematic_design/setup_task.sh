#!/bin/bash
set -e

echo "=== Setting up Transit Map Schematic Design Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the specific "B1 Bus Route" and Metro Map starter file
# We construct a valid .drawio XML file with Red/Blue lines and the Bus route.
cat > /home/ga/Diagrams/metro_system_map.drawio << 'EOF'
<mxfile host="Electron" modified="2023-10-01T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" etag="123456789" version="21.6.8" type="device">
  <diagram id="MetroMap" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Red Line -->
        <mxCell id="red_line" value="" style="endArrow=none;html=1;strokeWidth=12;strokeColor=#FF0000;rounded=0;edgeStyle=orthogonalEdgeStyle;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="100" y="300" as="sourcePoint" />
            <mxPoint x="700" y="300" as="targetPoint" />
            <Array as="points">
              <mxPoint x="400" y="300" />
            </Array>
          </mxGeometry>
        </mxCell>
        <!-- Blue Line -->
        <mxCell id="blue_line" value="" style="endArrow=none;html=1;strokeWidth=12;strokeColor=#0000FF;rounded=0;edgeStyle=orthogonalEdgeStyle;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="400" y="100" as="sourcePoint" />
            <mxPoint x="400" y="600" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- B1 Bus Route (To be deleted) -->
        <mxCell id="b1_bus" value="B1 Bus Route" style="endArrow=none;dashed=1;html=1;strokeWidth=4;strokeColor=#666666;edgeStyle=orthogonalEdgeStyle;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="100" y="320" as="sourcePoint" />
            <mxPoint x="600" y="500" as="targetPoint" />
            <Array as="points">
              <mxPoint x="100" y="400" />
              <mxPoint x="600" y="400" />
            </Array>
          </mxGeometry>
        </mxCell>
        <!-- Stations -->
        <mxCell id="st_west" value="Westside Terminal" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="60" y="270" width="120" height="30" as="geometry" />
        </mxCell>
        <mxCell id="tick_west" value="" style="shape=rect;fillColor=#000000;strokeColor=none;rotation=90;" vertex="1" parent="1">
           <mxGeometry x="90" y="295" width="20" height="10" as="geometry" />
        </mxCell>

        <mxCell id="st_stadium" value="Stadium" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="250" y="270" width="80" height="30" as="geometry" />
        </mxCell>
        <mxCell id="tick_stadium" value="" style="shape=rect;fillColor=#000000;strokeColor=none;rotation=90;" vertex="1" parent="1">
           <mxGeometry x="290" y="295" width="20" height="10" as="geometry" />
        </mxCell>

        <mxCell id="st_central" value="Central Plaza" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="410" y="270" width="100" height="30" as="geometry" />
        </mxCell>
        <mxCell id="tick_central" value="" style="shape=rect;fillColor=#000000;strokeColor=none;rotation=90;" vertex="1" parent="1">
           <mxGeometry x="390" y="295" width="20" height="10" as="geometry" />
        </mxCell>

        <mxCell id="st_market" value="Market St" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="420" y="150" width="80" height="30" as="geometry" />
        </mxCell>
        <mxCell id="tick_market" value="" style="shape=rect;fillColor=#000000;strokeColor=none;" vertex="1" parent="1">
           <mxGeometry x="395" y="160" width="20" height="10" as="geometry" />
        </mxCell>

        <mxCell id="st_airport" value="Airport" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="660" y="550" width="60" height="30" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# 3. Create Supporting Documents
cat > /home/ga/Desktop/silver_line_expansion_plan.txt << 'EOF'
=== METRO EXPANSION PROJECT: SILVER LINE ===

OBJECTIVE:
Integrate the new Silver Line service into the system map.

ROUTE:
1. Start: Westside Terminal (Interchange with Red Line)
2. Stop: Stadium (Interchange with Red Line)
3. Stop: Central Plaza (Major Interchange: Red, Blue, Silver Lines)
4. Stop: Tech Hub (New Station, East of Central Plaza)
5. End: Airport (New Service)

REQUIREMENTS:
- The Silver Line must be drawn as a continuous line using the specific color #A0A0A0.
- Use 45-degree or 90-degree angles ONLY. No curves.
- Where running parallel to the Red Line (Westside -> Central Plaza), keep lines distinct and non-overlapping.
- Rename "Market St" (on Blue Line) to "Financial District".
- Remove the "B1 Bus Route" completely - it is obsolete.

ACCESSIBILITY:
- Airport and Central Plaza are fully step-free. Add the standard "Wheelchair" symbol next to these station names.
EOF

cat > /home/ga/Desktop/design_style_guide.txt << 'EOF'
=== SYSTEM MAP STYLE GUIDE ===

COLORS:
- Red Line: #FF0000
- Blue Line: #0000FF
- Silver Line: #A0A0A0 (New!)
- Text: #000000

DIMENSIONS:
- Line Width: 12pt
- Station Ticks: Rectangle (small)
- Interchange Stations: Circle or Capsule shape (White fill, Black border)

SYMBOLS:
- Wheelchair: Use standard icon search "wheelchair" or "access".
EOF

chown ga:ga /home/ga/Diagrams/metro_system_map.drawio
chown ga:ga /home/ga/Desktop/silver_line_expansion_plan.txt
chown ga:ga /home/ga/Desktop/design_style_guide.txt

# 4. Record Start State
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Diagrams/metro_system_map.drawio > /tmp/initial_file_mtime.txt

# 5. Launch Application
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/metro_system_map.drawio > /dev/null 2>&1 &"

# 6. Handle Dialogs
echo "Waiting for window..."
sleep 5
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Dismiss update dialogs aggressively
echo "Dismissing dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="