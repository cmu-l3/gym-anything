#!/bin/bash
set -e

echo "=== Setting up Balanced Scorecard Strategy Map Task ==="

# Ensure directories exist
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 1. Create the draw.io template with empty swimlanes
DIAGRAM_FILE="/home/ga/Diagrams/hospital_strategy_map.drawio"
cat > "$DIAGRAM_FILE" << 'EOF'
<mxfile host="Electron" agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.0.4 Chrome/120.0.6099.109 Electron/28.1.0 Safari/537.36" version="24.0.4">
  <diagram name="Strategy Map" id="base-diagram">
    <mxGraphModel dx="1422" dy="832" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="lane1" value="Financial" style="swimlane;horizontal=0;whiteSpace=wrap;html=1;startSize=23;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="760" height="150" as="geometry" />
        </mxCell>
        <mxCell id="lane2" value="Customer" style="swimlane;horizontal=0;whiteSpace=wrap;html=1;startSize=23;" vertex="1" parent="1">
          <mxGeometry x="40" y="190" width="760" height="150" as="geometry" />
        </mxCell>
        <mxCell id="lane3" value="Internal Processes" style="swimlane;horizontal=0;whiteSpace=wrap;html=1;startSize=23;" vertex="1" parent="1">
          <mxGeometry x="40" y="340" width="760" height="150" as="geometry" />
        </mxCell>
        <mxCell id="lane4" value="Learning &amp; Growth" style="swimlane;horizontal=0;whiteSpace=wrap;html=1;startSize=23;" vertex="1" parent="1">
          <mxGeometry x="40" y="490" width="760" height="150" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF
chown ga:ga "$DIAGRAM_FILE"

# 2. Create the Strategic Plan document
PLAN_FILE="/home/ga/Desktop/strategic_plan.txt"
cat > "$PLAN_FILE" << 'EOF'
HOSPITAL SYSTEM - DIGITAL TRANSFORMATION STRATEGIC PLAN (2025-2027)
===================================================================

INSTRUCTIONS FOR CONSULTANT:
Please map these objectives into a Balanced Scorecard (BSC) visual strategy map using the provided template.

1. OBJECTIVES BY PERSPECTIVE
----------------------------
Place these as Rounded Rectangle shapes in the corresponding swim lanes.

FINANCIAL PERSPECTIVE (Top Lane)
- Increase Operating Margin
- Grow Revenue from Digital Services
- Reduce Cost per Patient Encounter

CUSTOMER PERSPECTIVE (Second Lane)
- Improve Patient Satisfaction
- Reduce Patient Wait Times
- Expand Telehealth Access
- Enhance Patient Portal Adoption

INTERNAL PROCESSES PERSPECTIVE (Third Lane)
- Integrate Electronic Health Records
- Automate Clinical Workflows
- Strengthen Cybersecurity Posture
- Optimize Supply Chain Management
- Reduce Hospital-Acquired Infections

LEARNING & GROWTH PERSPECTIVE (Bottom Lane)
- Develop Digital Literacy Training
- Recruit Health Informatics Talent
- Foster Innovation Culture
- Upgrade IT Infrastructure

2. CAUSE-AND-EFFECT RELATIONSHIPS (Draw Arrows)
-----------------------------------------------
Draw directional arrows (edges) connecting these objectives:

[Foundation -> Process]
- Upgrade IT Infrastructure -> Integrate Electronic Health Records
- Upgrade IT Infrastructure -> Strengthen Cybersecurity Posture
- Develop Digital Literacy Training -> Automate Clinical Workflows
- Recruit Health Informatics Talent -> Integrate Electronic Health Records

[Process -> Customer]
- Integrate Electronic Health Records -> Automate Clinical Workflows
- Automate Clinical Workflows -> Reduce Patient Wait Times
- Strengthen Cybersecurity Posture -> Improve Patient Satisfaction
- Optimize Supply Chain Management -> Reduce Cost per Patient Encounter
- Reduce Hospital-Acquired Infections -> Improve Patient Satisfaction

[Customer/Foundation -> Customer]
- Foster Innovation Culture -> Expand Telehealth Access
- Expand Telehealth Access -> Enhance Patient Portal Adoption
- Expand Telehealth Access -> Reduce Patient Wait Times
- Reduce Patient Wait Times -> Improve Patient Satisfaction

[Customer -> Financial]
- Enhance Patient Portal Adoption -> Grow Revenue from Digital Services
- Improve Patient Satisfaction -> Increase Operating Margin
- Reduce Cost per Patient Encounter -> Increase Operating Margin
- Grow Revenue from Digital Services -> Increase Operating Margin

3. VISUAL STYLE REQUIREMENTS
----------------------------
Color code the objectives (Fill Color) based on their perspective:
- Financial: #FFD700 (Gold)
- Customer: #4DA6FF (Blue)
- Internal Processes: #66CC66 (Green)
- Learning & Growth: #FF9966 (Orange)

4. DELIVERABLE
--------------
Export the final diagram as a PDF to: ~/Diagrams/hospital_strategy_map.pdf
EOF
chown ga:ga "$PLAN_FILE"

# 3. Setup anti-gaming
date +%s > /tmp/task_start_time.txt
grep -c "mxCell" "$DIAGRAM_FILE" > /tmp/initial_cell_count.txt

# 4. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox \"$DIAGRAM_FILE\" > /dev/null 2>&1 &"

# 5. Handle update dialogs (Aggressive dismissal)
sleep 5
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "update\|confirm"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    else
        break
    fi
done
# Safety extra escapes
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="