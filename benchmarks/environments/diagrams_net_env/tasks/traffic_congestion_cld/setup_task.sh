#!/bin/bash
set -e

echo "=== Setting up Traffic Congestion CLD Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Requirements Text File
cat > /home/ga/Desktop/cld_requirements.txt << 'EOF'
SYSTEM DYNAMICS MODEL SPECIFICATION: URBAN TRAFFIC CONGESTION
=============================================================

TASK OVERVIEW
-------------
You need to complete the Causal Loop Diagram (CLD) in '~/Diagrams/traffic_congestion_cld.drawio'.
The diagram currently has 6 variables. You must add 8 more variables, draw the connecting arrows,
label polarities, and annotate the feedback loops.

NOTATION GUIDE
--------------
- Link Polarity (+): Variables change in the SAME direction (e.g., more A -> more B).
- Link Polarity (-): Variables change in OPPOSITE directions (e.g., more A -> less B).
- R-Loop: Reinforcing Loop (Positive Feedback).
- B-Loop: Balancing Loop (Negative Feedback).

MISSING VARIABLES TO ADD
------------------------
1. Attractiveness of Driving
2. Road Expansion Budget
3. Remote Work Adoption
4. Air Quality
5. Fuel Consumption
6. CO2 Emissions
7. Population Growth
8. Housing Demand Near Transit

CAUSAL LINKS & POLARITIES (Draw these arrows and label with + or -)
-------------------------------------------------------------------
Existing (Label these):
- Traffic Volume -> Road Congestion (+)
- Road Congestion -> Travel Time (+)
- Road Capacity -> Road Congestion (-)

Loop R1: Induced Demand
- Road Expansion Budget -> Road Capacity (+)
- Travel Time -> Attractiveness of Driving (-)
- Attractiveness of Driving -> Traffic Volume (+)
- (Closing the loop: Road Congestion -> Travel Time is already there)
- (Closing the loop: Traffic Volume -> Road Congestion is already there)
- (Note: High Road Congestion creates political pressure for expansion)
- Road Congestion -> Road Expansion Budget (+)

Loop B1: Public Transit Shift
- Travel Time -> Public Transit Ridership (+)
- Public Transit Ridership -> Traffic Volume (-)

Loop B2: Remote Work Escape
- Travel Time -> Remote Work Adoption (+)
- Remote Work Adoption -> Traffic Volume (-)

Loop B3: Environmental Limit
- Traffic Volume -> Fuel Consumption (+)
- Fuel Consumption -> CO2 Emissions (+)
- CO2 Emissions -> Air Quality (-)   [More emissions = lower quality]
- Air Quality -> Road Expansion Budget (-) [Poor air quality limits expansion approval]

Loop R2: Economic Growth Engine
- Road Capacity -> Economic Activity (+) [Better infrastructure aids economy]
- Economic Activity -> Population Growth (+)
- Population Growth -> Traffic Volume (+)

Loop B4: Transit Oriented Development (Bonus/Implicit)
- Public Transit Ridership -> Housing Demand Near Transit (+)
- Housing Demand Near Transit -> Population Growth (+)

FINAL OUTPUT
------------
1. Ensure all 14 variables are on the diagram.
2. Ensure all arrows have a '+' or '-' text label near the arrowhead.
3. Place a text label "R1: Induced Demand" inside the R1 loop.
4. Place text labels for R2, B1, B2, B3 inside their respective loops.
5. Add a legend explaining +, -, R, and B.
6. Export as PDF to ~/Diagrams/traffic_congestion_cld.pdf.
EOF

# 3. Create the Starter Draw.io File (Uncompressed XML)
# Contains 6 initial nodes arranged in a circle
cat > /home/ga/Diagrams/traffic_congestion_cld.drawio << 'XML_EOF'
<mxfile host="Electron" modified="2024-01-01T00:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/26.0.9 Chrome/128.0.6613.186 Electron/32.2.5 Safari/537.36" version="26.0.9" type="device">
  <diagram id="traffic_cld_page" name="Traffic Congestion CLD">
    <mxGraphModel dx="1422" dy="868" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- Initial Variables -->
        <mxCell id="var_traffic" value="Traffic Volume" style="rounded=1;whiteSpace=wrap;html=1;arcSize=20;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="360" y="280" width="120" height="40" as="geometry" />
        </mxCell>
        <mxCell id="var_congestion" value="Road Congestion" style="rounded=1;whiteSpace=wrap;html=1;arcSize=20;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="360" y="400" width="120" height="40" as="geometry" />
        </mxCell>
        <mxCell id="var_traveltime" value="Travel Time" style="rounded=1;whiteSpace=wrap;html=1;arcSize=20;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="360" y="520" width="120" height="40" as="geometry" />
        </mxCell>
        <mxCell id="var_capacity" value="Road Capacity" style="rounded=1;whiteSpace=wrap;html=1;arcSize=20;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="120" y="400" width="120" height="40" as="geometry" />
        </mxCell>
        <mxCell id="var_transit" value="Public Transit&#xa;Ridership" style="rounded=1;whiteSpace=wrap;html=1;arcSize=20;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="600" y="400" width="120" height="40" as="geometry" />
        </mxCell>
        <mxCell id="var_econ" value="Economic&#xa;Activity" style="rounded=1;whiteSpace=wrap;html=1;arcSize=20;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="360" y="100" width="120" height="40" as="geometry" />
        </mxCell>

        <!-- Initial Unlabeled Connections -->
        <mxCell id="edge_1" value="" style="endArrow=classic;html=1;curved=1;" edge="1" parent="1" source="var_traffic" target="var_congestion">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>
        <mxCell id="edge_2" value="" style="endArrow=classic;html=1;curved=1;" edge="1" parent="1" source="var_congestion" target="var_traveltime">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>
        <mxCell id="edge_3" value="" style="endArrow=classic;html=1;curved=1;" edge="1" parent="1" source="var_capacity" target="var_congestion">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML_EOF

# 4. Set Permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop
chmod 644 /home/ga/Diagrams/traffic_congestion_cld.drawio
chmod 644 /home/ga/Desktop/cld_requirements.txt

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
grep -c "vertex=\"1\"" /home/ga/Diagrams/traffic_congestion_cld.drawio > /tmp/initial_vertex_count.txt

# 6. Launch Draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/traffic_congestion_cld.drawio &"

# 7. Wait and Handle Dialogs
sleep 5
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Draw.io window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Aggressively dismiss update dialogs
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="