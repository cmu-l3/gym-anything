#!/bin/bash
set -e
echo "=== Setting up ESI Triage Decision Tree task ==="

# 1. Prepare Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Partial .drawio File
# This XML defines a diagram with Start -> Decision A -> Decision B -> TODO Note
cat > /home/ga/Diagrams/esi_triage_tree.drawio << 'DRAWIOEOF'
<?xml version="1.0" encoding="UTF-8"?>
<mxfile host="Electron" modified="2024-03-01T10:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/26.0.9 Chrome/120.0.6099.109 Electron/28.1.0 Safari/537.36" etag="initial_setup" version="26.0.9" type="device">
  <diagram name="Page-1" id="page1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="start" value="Patient arrives at triage" style="ellipse;whiteSpace=wrap;html=1;fillColor=#f5f5f5;fontColor=#333333;strokeColor=#666666;" vertex="1" parent="1">
          <mxGeometry x="365" y="40" width="120" height="80" as="geometry" />
        </mxCell>
        <mxCell id="decA" value="A. Requires immediate&lt;br&gt;lifesaving intervention?" style="rhombus;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="325" y="160" width="200" height="100" as="geometry" />
        </mxCell>
        <mxCell id="edge1" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="start" target="decA">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="esi1" value="ESI Level 1&lt;br&gt;Resuscitation" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="600" y="180" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="edge2" value="Yes" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" parent="1" source="decA" target="esi1">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="decB" value="B. High risk situation?&lt;br&gt;Confused/Lethargic?&lt;br&gt;Severe pain/distress?" style="rhombus;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="325" y="300" width="200" height="110" as="geometry" />
        </mxCell>
        <mxCell id="edge3" value="No" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="decA" target="decB">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="esi2" value="ESI Level 2&lt;br&gt;Emergent" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="600" y="325" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="edge4" value="Yes" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" parent="1" source="decB" target="esi2">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
        <mxCell id="todo" value="TODO: Continue algorithm here&lt;br&gt;(See ~/Desktop/esi_v4_algorithm.txt)" style="shape=note;whiteSpace=wrap;html=1;backgroundOutline=1;darkOpacity=0.05;fillColor=#f8cecc;strokeColor=#b85450;fontColor=#FF0000;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="325" y="460" width="200" height="80" as="geometry" />
        </mxCell>
        <mxCell id="edge5" value="No" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;dashed=1;strokeColor=#FF0000;" edge="1" parent="1" source="decB" target="todo">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
DRAWIOEOF

# 3. Create the Algorithm Spec File
cat > /home/ga/Desktop/esi_v4_algorithm.txt << 'TXTEOF'
================================================================================
ESI v4 (Emergency Severity Index) Triage Algorithm Specification
================================================================================

You need to complete the diagram starting from the "No" branch of Decision B.

DECISION C: Resource Prediction
--------------------------------------------------------------------------------
Shape: Diamond
Text: "How many different types of resources will this patient need?"
Input: Comes from Decision B (No)

Branches:
1. "None (0)" -> Assign ESI Level 5
2. "One (1)"  -> Assign ESI Level 4
3. "Many (>=2)" -> Go to Decision D

DECISION D: Vital Signs
--------------------------------------------------------------------------------
Shape: Diamond
Text: "Are vital signs in the danger zone?"
Input: Comes from Decision C (Many)

Branches:
1. "No" -> Assign ESI Level 3
2. "Yes" -> UPGRADE to ESI Level 2 (Draw arrow connecting back to ESI Level 2)

TERMINAL NODES (ESI Levels)
--------------------------------------------------------------------------------
Shape: Rounded Rectangle
Color Coding (MANDATORY):
- ESI Level 1 (Resuscitation): RED
- ESI Level 2 (Emergent): ORANGE
- ESI Level 3 (Urgent): YELLOW
- ESI Level 4 (Less Urgent): GREEN
- ESI Level 5 (Non-Urgent): BLUE

LEGEND
--------------------------------------------------------------------------------
Add a small legend showing the 5 colors and their meaning.

CLEANUP
--------------------------------------------------------------------------------
Remove the red "TODO" note and the dashed arrow connecting to it.
TXTEOF

# 4. Set Permissions
chown ga:ga /home/ga/Diagrams/esi_triage_tree.drawio
chown ga:ga /home/ga/Desktop/esi_v4_algorithm.txt

# 5. Record Initial State
md5sum /home/ga/Diagrams/esi_triage_tree.drawio > /tmp/initial_hash.txt
date +%s > /tmp/task_start_time.txt

# 6. Launch draw.io
echo "Launching draw.io..."
export DISPLAY=:1
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/esi_triage_tree.drawio > /tmp/drawio.log 2>&1 &"

# 7. Wait for Window and Handle Updates
echo "Waiting for draw.io window..."
for i in {1..30}; do
    if wmctrl -l | grep -qi "diagrams.net\|draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Aggressively dismiss update dialogs (common in draw.io AppImage)
sleep 3
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    xdotool key Escape
    sleep 0.5
done

# Maximize Window
wmctrl -r "diagrams.net" -b add,maximized_vert,maximized_horz 2>/dev/null || true
wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial Screenshot
scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="