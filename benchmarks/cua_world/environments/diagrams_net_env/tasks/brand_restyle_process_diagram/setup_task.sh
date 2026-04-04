#!/bin/bash
set -e
echo "=== Setting up brand_restyle_process_diagram task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
su - ga -c "mkdir -p /home/ga/Diagrams/exports"
su - ga -c "mkdir -p /home/ga/Desktop"

# Create the initial (default-styled) customer onboarding flowchart
cat > /home/ga/Diagrams/customer_onboarding.drawio << 'DRAWIOEOF'
<mxfile host="app.diagrams.net" modified="2024-01-15T10:00:00.000Z" agent="draw.io" version="22.0.0" type="device">
  <diagram id="onboarding-flow" name="Customer Onboarding">
    <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1654" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <!-- Title -->
        <mxCell id="title1" value="Customer Onboarding Process" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;fontSize=18;" vertex="1" parent="1">
          <mxGeometry x="540" y="20" width="400" height="40" as="geometry"/>
        </mxCell>
        <!-- Subtitle -->
        <mxCell id="subtitle1" value="Version: Draft — Pending Brand Review" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;fontSize=11;fontStyle=2;" vertex="1" parent="1">
          <mxGeometry x="580" y="55" width="320" height="25" as="geometry"/>
        </mxCell>
        <!-- Start -->
        <mxCell id="start1" value="Start" style="ellipse;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="680" y="100" width="120" height="50" as="geometry"/>
        </mxCell>
        <!-- Process: Receive Signup -->
        <mxCell id="p1" value="Receive Signup Form" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="660" y="190" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e1" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="start1" target="p1" parent="1"/>
        <!-- Process: Verify Email -->
        <mxCell id="p2" value="Verify Email Address" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="660" y="280" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e2" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p1" target="p2" parent="1"/>
        <!-- Decision: Email Verified? -->
        <mxCell id="d1" value="Email Verified?" style="rhombus;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="680" y="370" width="120" height="80" as="geometry"/>
        </mxCell>
        <mxCell id="e3" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p2" target="d1" parent="1"/>
        <!-- No path back -->
        <mxCell id="e3no" value="No" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d1" target="p2" parent="1">
          <mxGeometry relative="1" as="geometry">
            <Array as="points"><mxPoint x="870" y="410"/><mxPoint x="870" y="305"/></Array>
          </mxGeometry>
        </mxCell>
        <!-- Process: Create Account -->
        <mxCell id="p3" value="Create Account" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="660" y="490" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e4" value="Yes" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d1" target="p3" parent="1"/>
        <!-- Process: Assign Specialist -->
        <mxCell id="p4" value="Assign Onboarding Specialist" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="660" y="580" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e5" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p3" target="p4" parent="1"/>
        <!-- Process: Schedule Kickoff -->
        <mxCell id="p5" value="Schedule Kickoff Call" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="660" y="670" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e6" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p4" target="p5" parent="1"/>
        <!-- Process: Conduct Kickoff -->
        <mxCell id="p6" value="Conduct Kickoff Call" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="660" y="760" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e7" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p5" target="p6" parent="1"/>
        <!-- Process: Configure Workspace -->
        <mxCell id="p7" value="Configure Workspace" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="370" y="190" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e8" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p6" target="p7" parent="1">
          <mxGeometry relative="1" as="geometry">
            <Array as="points"><mxPoint x="450" y="785"/></Array>
          </mxGeometry>
        </mxCell>
        <!-- Process: Import Data -->
        <mxCell id="p8" value="Import Customer Data" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="370" y="280" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e9" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p7" target="p8" parent="1"/>
        <!-- Decision: Data Import Successful? -->
        <mxCell id="d2" value="Data Import Successful?" style="rhombus;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="390" y="370" width="120" height="80" as="geometry"/>
        </mxCell>
        <mxCell id="e10" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p8" target="d2" parent="1"/>
        <!-- No path retry -->
        <mxCell id="e10no" value="No" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d2" target="p8" parent="1">
          <mxGeometry relative="1" as="geometry">
            <Array as="points"><mxPoint x="570" y="410"/><mxPoint x="570" y="305"/></Array>
          </mxGeometry>
        </mxCell>
        <!-- Process: Enable Integrations -->
        <mxCell id="p9" value="Enable Integrations" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="370" y="490" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e11" value="Yes" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d2" target="p9" parent="1"/>
        <!-- Process: Run Tests -->
        <mxCell id="p10" value="Run Acceptance Tests" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="370" y="580" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e12" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p9" target="p10" parent="1"/>
        <!-- Decision: Tests Passed? -->
        <mxCell id="d3" value="Tests Passed?" style="rhombus;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="390" y="670" width="120" height="80" as="geometry"/>
        </mxCell>
        <mxCell id="e13" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p10" target="d3" parent="1"/>
        <!-- No path back to configure -->
        <mxCell id="e13no" value="No" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d3" target="p7" parent="1">
          <mxGeometry relative="1" as="geometry">
            <Array as="points"><mxPoint x="280" y="710"/><mxPoint x="280" y="215"/></Array>
          </mxGeometry>
        </mxCell>
        <!-- Process: Training -->
        <mxCell id="p11" value="Conduct Training Session" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="100" y="280" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e14" value="Yes" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d3" target="p11" parent="1">
          <mxGeometry relative="1" as="geometry">
            <Array as="points"><mxPoint x="180" y="710"/></Array>
          </mxGeometry>
        </mxCell>
        <!-- Decision: Training Complete? -->
        <mxCell id="d4" value="Training Complete?" style="rhombus;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="120" y="370" width="120" height="80" as="geometry"/>
        </mxCell>
        <mxCell id="e15" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p11" target="d4" parent="1"/>
        <!-- No path retry training -->
        <mxCell id="e15no" value="No" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d4" target="p11" parent="1">
          <mxGeometry relative="1" as="geometry">
            <Array as="points"><mxPoint x="50" y="410"/><mxPoint x="50" y="305"/></Array>
          </mxGeometry>
        </mxCell>
        <!-- Process: Documentation -->
        <mxCell id="p12" value="Deliver Documentation Package" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="100" y="490" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e16" value="Yes" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="d4" target="p12" parent="1"/>
        <!-- Process: Set Up Billing -->
        <mxCell id="p13" value="Set Up Billing" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="100" y="580" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e17" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p12" target="p13" parent="1"/>
        <!-- Process: Activate Production -->
        <mxCell id="p14" value="Activate Production Access" style="whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="100" y="670" width="160" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e18" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p13" target="p14" parent="1"/>
        <!-- End -->
        <mxCell id="end1" value="Onboarding Complete" style="ellipse;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="110" y="760" width="140" height="50" as="geometry"/>
        </mxCell>
        <mxCell id="e19" style="edgeStyle=orthogonalEdgeStyle;" edge="1" source="p14" target="end1" parent="1"/>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
DRAWIOEOF
chown ga:ga /home/ga/Diagrams/customer_onboarding.drawio
chmod 644 /home/ga/Diagrams/customer_onboarding.drawio

# Save a copy of original for verification comparison
cp /home/ga/Diagrams/customer_onboarding.drawio /tmp/customer_onboarding_original.drawio

# Create brand style guide
cat > /home/ga/Desktop/brand_style_guide.txt << 'GUIDEEOF'
===============================================================
         ACME SaaS Inc. — Diagram Brand Style Guide
                   Version 3.1 (2024-Q4)
===============================================================

This guide defines the required visual styling for all
process diagrams published in customer-facing materials.

---------------------------------------------------------------
1. PROCESS STEP RECTANGLES (task/action boxes)
---------------------------------------------------------------
   Fill Color:       #1B365D  (ACME Navy)
   Font Color:       #FFFFFF  (White)
   Font Family:      Arial
   Font Size:        13pt
   Font Style:       Bold
   Corner Radius:    Rounded (use rounded=1 in draw.io)
   Border:           No visible border (strokeColor=none or match fill)
   Shadow:           Enabled

---------------------------------------------------------------
2. DECISION DIAMONDS (conditional branch points)
---------------------------------------------------------------
   Fill Color:       #E87722  (ACME Orange)
   Font Color:       #FFFFFF  (White)
   Font Family:      Arial
   Font Size:        12pt
   Font Style:       Bold
   Border:           No visible border (strokeColor=none or match fill)
   Shadow:           Enabled

---------------------------------------------------------------
3. START / END TERMINATORS (ellipses or stadium shapes)
---------------------------------------------------------------
   Fill Color:       #00A3E0  (ACME Sky Blue)
   Font Color:       #FFFFFF  (White)
   Font Family:      Arial
   Font Size:        14pt
   Font Style:       Bold
   Border:           No visible border (strokeColor=none or match fill)
   Shadow:           Enabled

---------------------------------------------------------------
4. CONNECTORS / ARROWS (edges between shapes)
---------------------------------------------------------------
   Stroke Color:     #4A4A4A  (Dark Gray)
   Stroke Width:     2pt
   Arrow Style:      Standard (block arrow end)
   Label Font:       Arial, 11pt
   Label Color:      #4A4A4A  (Dark Gray)

---------------------------------------------------------------
5. ANNOTATION TEXT (titles, subtitles, notes)
---------------------------------------------------------------
   Title Font:       Arial, 20pt, Bold
   Title Color:      #1B365D  (ACME Navy)
   Subtitle Font:    Arial, 12pt, Italic
   Subtitle Color:   #666666  (Medium Gray)

---------------------------------------------------------------
6. DIAGRAM BACKGROUND
---------------------------------------------------------------
   Background Color: #F5F5F5  (Light Gray)

---------------------------------------------------------------
7. GENERAL RULES
---------------------------------------------------------------
   • ALL shapes must have shadows enabled
   • Do NOT change any text labels or diagram structure
   • Do NOT add or remove any shapes or connections
   • Only visual styling should change

===============================================================
   OUTPUT REQUIREMENTS
===============================================================
   After applying all styles:
   1. Save the restyled .drawio file
   2. Export as PNG to: ~/Diagrams/exports/customer_onboarding.png
   3. Export as PDF to: ~/Diagrams/exports/customer_onboarding.pdf
===============================================================
GUIDEEOF
chown ga:ga /home/ga/Desktop/brand_style_guide.txt

# Kill any existing draw.io processes
pkill -f "drawio" 2>/dev/null || true
sleep 2

# Launch draw.io with the file
echo "Launching draw.io..."
export DISPLAY=:1
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/customer_onboarding.drawio > /tmp/drawio.log 2>&1 &"

# Wait for draw.io to start
echo "Waiting for draw.io window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "draw\|diagram\|onboarding"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done
sleep 5

# Aggressively dismiss update dialogs
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done
# Try clicking "Cancel" area just in case (approximate for 1920x1080)
DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true
sleep 1

# Maximize draw.io window
DISPLAY=:1 wmctrl -r "diagrams.net" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="