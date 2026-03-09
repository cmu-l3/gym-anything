#!/bin/bash
set -e

echo "=== Setting up Optical Ray Tracing Task ==="

# 1. Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Diagrams/exports

# 2. Create Specifications File
cat > /home/ga/Desktop/telescope_specs.txt << 'EOF'
KEPLERIAN TELESCOPE DESIGN SPECIFICATIONS
=========================================
Project: EDU-TELE-01
Date: 2026-05-15

SYSTEM PARAMETERS:
------------------
Type: Refractor (Keplerian)
Magnification Goal: 5x

COMPONENT SPECIFICATIONS:
1. Objective Lens (L1):
   - Type: Bi-Convex Positive
   - Focal Length (fo): 400 mm
   - Diameter: 60 mm

2. Eyepiece Lens (L2):
   - Type: Bi-Convex Positive
   - Focal Length (fe): 80 mm
   - Diameter: 20 mm

DIAGRAMMING STANDARDS:
----------------------
- Scale: 10 pixels (1 grid square) = 10 mm
- Total System Length: fo + fe
- Orientation: Light enters from Left
- Required Rays: 3 (Top marginal, Axial, Bottom marginal)
EOF

# 3. Create Starter Draw.io File (XML)
# Includes a dashed Optical Axis line and grid settings
cat > /home/ga/Diagrams/telescope_schematic.drawio << 'EOF'
<mxfile host="Electron" modified="2024-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.0.0 Chrome/120.0.0.0 Electron/28.0.0 Safari/537.36" etag="starter" version="24.0.0" type="device">
  <diagram id="optics-1" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Optical Axis -->
        <mxCell id="axis" value="" style="endArrow=none;dashed=1;html=1;strokeWidth=1;strokeColor=#999999;" parent="1" edge="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="40" y="400" as="sourcePoint" />
            <mxPoint x="760" y="400" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Origin Marker -->
        <mxCell id="origin" value="0 mm" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;fontColor=#666666;" parent="1" vertex="1">
          <mxGeometry x="30" y="410" width="60" height="30" as="geometry" />
        </mxCell>
        <!-- Ruler Guide Text -->
        <mxCell id="scale_guide" value="Scale: 1 grid (10px) = 10mm" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontStyle=1" parent="1" vertex="1">
          <mxGeometry x="40" y="40" width="200" height="30" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown -R ga:ga /home/ga/Desktop /home/ga/Diagrams

# 4. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/telescope_schematic.drawio > /tmp/drawio.log 2>&1 &"

# 5. Handle Update Dialogs (Anti-Blocking)
echo "Waiting for window..."
sleep 5
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Dismissing potential update dialogs..."
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
        DISPLAY=:1 xdotool key Escape
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Record Task Start Time
date +%s > /tmp/task_start_time.txt
stat -c %Y /home/ga/Diagrams/telescope_schematic.drawio > /tmp/initial_file_mtime.txt

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="