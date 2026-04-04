#!/bin/bash
set -e

echo "=== Setting up Emergency Evacuation Floor Plan Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Bare Floor Plan (Starter Diagram)
# This XML defines the walls of a ~15 room office floor but no labels/symbols
cat > /home/ga/Diagrams/3rd_floor_plan.drawio << 'EOF'
<mxfile host="Electron" modified="2024-03-01T10:00:00.000Z" agent="Mozilla/5.0" version="22.1.0" type="device">
  <diagram name="3rd Floor Layout" id="floorplan3">
    <mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Building Shell -->
        <mxCell id="wall_outer" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeWidth=3;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="1000" height="600" as="geometry" />
        </mxCell>
        <!-- Stairwell A (Top Left) -->
        <mxCell id="swa" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="120" height="160" as="geometry" />
        </mxCell>
        <!-- Stairwell B (Bottom Left) -->
        <mxCell id="swb" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry x="40" y="480" width="120" height="160" as="geometry" />
        </mxCell>
        <!-- Elevator Shaft (Right) -->
        <mxCell id="elv" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1e1e1;strokeWidth=2;" vertex="1" parent="1">
          <mxGeometry x="800" y="250" width="100" height="150" as="geometry" />
        </mxCell>
        <!-- Corridor Vertical (West) -->
        <mxCell id="corr_w" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=none;" vertex="1" parent="1">
          <mxGeometry x="160" y="40" width="80" height="600" as="geometry" />
        </mxCell>
        <!-- Room 301 -->
        <mxCell id="r301" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="240" y="40" width="160" height="120" as="geometry" />
        </mxCell>
        <!-- Room 302 -->
        <mxCell id="r302" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="240" y="160" width="160" height="120" as="geometry" />
        </mxCell>
        <!-- Room 303 -->
        <mxCell id="r303" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="240" y="280" width="160" height="120" as="geometry" />
        </mxCell>
        <!-- Room 304 (Open Workspace) -->
        <mxCell id="r304" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="440" y="40" width="300" height="360" as="geometry" />
        </mxCell>
        <!-- Room 305 (Server) -->
        <mxCell id="r305" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="780" y="40" width="120" height="100" as="geometry" />
        </mxCell>
        <!-- Room 306 (Conf A) -->
        <mxCell id="r306" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="440" y="440" width="200" height="200" as="geometry" />
        </mxCell>
        <!-- Room 307 (Conf B) -->
        <mxCell id="r307" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="640" y="440" width="200" height="200" as="geometry" />
        </mxCell>
        <!-- Room 308 (Kitchen) -->
        <mxCell id="r308" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="240" y="440" width="160" height="200" as="geometry" />
        </mxCell>
        <!-- Restrooms -->
        <mxCell id="rr" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="920" y="40" width="120" height="200" as="geometry" />
        </mxCell>
        <!-- Reception/Lobby -->
        <mxCell id="lobby" value="" style="rounded=0;whiteSpace=wrap;html=1;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="860" y="440" width="180" height="200" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# 3. Create Requirements Document
cat > /home/ga/Desktop/evacuation_plan_requirements.txt << 'EOF'
EMERGENCY EVACUATION FLOOR PLAN REQUIREMENTS
Building C - 3rd Floor
Prepared by: Safety Officer, J. Mercer
Date: 2025-01-15
Reference: NFPA 101 Life Safety Code, Chapter 7

=== ROOM SCHEDULE ===
Room ID  | Name                    | Notes
---------|-------------------------|-------
SW-A     | Stairwell A             | Top-Left
301      | Executive Office        | West Wall
302      | Finance Office          | West Wall
303      | HR Office               | West Wall
304      | Open Workspace          | Center North
305      | Server Room             | North Wall
306      | Conference Room A       | Center South
307      | Conference Room B       | Center South
308      | Kitchen / Break Room    | West Wall (South)
309/310  | Restrooms               | North East
312      | Reception / Lobby       | South East (Main Entrance)
SW-B     | Stairwell B             | Bottom-Left
ELV      | Elevator                | Do not use in fire

=== FIRE EXIT LOCATIONS (3 required) ===
1. Stairwell A (Top-Left)
2. Stairwell B (Bottom-Left)
3. Main Entrance (Bottom-Right/Lobby)
* Mark with red "EXIT" labels

=== SAFETY EQUIPMENT ===
Fire Extinguishers (Red Symbol):
1. Outside Room 301
2. Inside Open Workspace (North Wall)
3. Between Conference Rooms A and B
4. Inside Kitchen
5. Reception Area

First Aid Stations (Green Symbol):
1. Kitchen
2. Reception Desk

=== EVACUATION ROUTES ===
- Primary Routes: Solid GREEN arrows pointing to nearest exit
- Secondary Routes: Dashed ORANGE arrows (alternates)
- Assembly Point: "Parking Lot B" (Mark outside building footprint)

=== LEGEND & TITLE ===
- Add a legend box explaining symbols (Exit, Routes, Extinguisher, First Aid, Assembly)
- Title: "3rd Floor Emergency Evacuation Plan — Building C"
EOF

# 4. Set Permissions
chown ga:ga /home/ga/Diagrams/3rd_floor_plan.drawio
chown ga:ga /home/ga/Desktop/evacuation_plan_requirements.txt
chmod 644 /home/ga/Diagrams/3rd_floor_plan.drawio
chmod 644 /home/ga/Desktop/evacuation_plan_requirements.txt

# 5. Clean up previous runs
rm -f /home/ga/Diagrams/3rd_floor_evacuation.pdf 2>/dev/null || true

# 6. Record Initial State
echo "16" > /tmp/initial_shape_count
date +%s > /tmp/task_start_time.txt

# 7. Launch Application
echo "Launching draw.io..."
pkill -f drawio 2>/dev/null || true
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/3rd_floor_plan.drawio > /tmp/drawio.log 2>&1 &"

# 8. Handle Update Dialog (Robust Loop)
echo "Waiting for draw.io..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

echo "Dismissing update dialogs..."
for i in {1..15}; do
    # Try Escape
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Try Tab+Enter (Select Cancel)
    DISPLAY=:1 xdotool key Tab Tab Return 2>/dev/null || true
    sleep 0.5
    
    # If main window title is visible and active, we might be good
    if DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null | grep -qi "3rd_floor_plan"; then
        echo "Main diagram appears focused."
        break
    fi
done

# 9. Maximize Window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 10. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="