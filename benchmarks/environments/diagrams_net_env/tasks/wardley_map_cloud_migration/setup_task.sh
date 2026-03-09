#!/bin/bash
set -e

echo "=== Setting up Wardley Map Task ==="

# Ensure directories exist
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 1. Create the Specification Text File
cat > /home/ga/Desktop/cloud_migration_strategy.txt << 'EOF'
WARDLEY MAP SPECIFICATION: FintechCo Cloud Migration Strategy Q3 2025
=====================================================================

INSTRUCTIONS:
Create a Wardley Map in draw.io using the provided template.
- X-Axis: Evolution (Genesis -> Custom -> Product -> Commodity)
- Y-Axis: Value Chain (Visible -> Invisible)

COLOR CODING SCHEME:
- User-Facing: Blue (#4A90D9)
- Business Logic: Green (#7AB648)
- Platform/Infra: Orange (#F5A623)
- Data: Purple (#9B59B6)

COMPONENTS (Name | Category | Evolution X% | Value Chain Y%):
--------------------------------------------------------------
1. Customer Mobile App    | User-Facing    | 70% | 95%
2. Customer Web Portal    | User-Facing    | 75% | 90%
3. Partner API Gateway    | User-Facing    | 60% | 85%
4. Payment Processing     | Business Logic | 80% | 75%
5. KYC/AML Engine         | Business Logic | 45% | 70%
6. Loan Origination       | Business Logic | 35% | 72%
7. Risk Scoring           | Business Logic | 40% | 65%
8. Notification Service   | Business Logic | 70% | 60%
9. API Management         | Platform       | 75% | 50%
10. Container Orchestration| Platform       | 65% | 45%
11. CI/CD Pipeline        | Platform       | 60% | 40%
12. Identity Provider     | Platform       | 80% | 55%
13. Monitoring/Observability| Platform     | 55% | 35%
14. Relational Database   | Data           | 85% | 25%
15. Event Streaming       | Data           | 55% | 30%
16. Data Warehouse        | Data           | 60% | 20%
17. Object Storage        | Data           | 90% | 15%
18. ML Model Registry     | Data           | 25% | 22%

DEPENDENCIES (Draw solid arrows FROM dependent TO dependency):
--------------------------------------------------------------
- Customer Mobile App -> Payment Processing, Loan Origination, Identity Provider
- Customer Web Portal -> Payment Processing, Loan Origination, Identity Provider
- Partner API Gateway -> Loan Origination, Risk Scoring
- Payment Processing -> Relational Database, API Management
- Loan Origination -> Risk Scoring, KYC/AML Engine, Relational Database
- Risk Scoring -> ML Model Registry, Data Warehouse
- KYC/AML Engine -> Relational Database
- Notification Service -> Event Streaming
- All Business Logic apps (4,5,6,7,8) -> Container Orchestration
- Container Orchestration -> Monitoring/Observability, CI/CD Pipeline

EVOLUTION ARROWS (Draw THICK dashed arrows pointing right):
-----------------------------------------------------------
- KYC/AML Engine: Move from 45% -> 70% (Buy SaaS)
- Container Orchestration: Move from 65% -> 85% (Managed K8s)
- Monitoring/Observability: Move from 55% -> 80%
- CI/CD Pipeline: Move from 60% -> 80%
- Event Streaming: Move from 55% -> 75%
- ML Model Registry: Move from 25% -> 55%

ANNOTATIONS (Add text callouts):
--------------------------------
1. Near KYC/AML: "Replace Legacy Vendor"
2. Near Container Orchestration: "Migrate to EKS"
3. Near Data Warehouse: "Consolidate Silos"
EOF

# 2. Create the Starter Diagram (Axes Only)
# This constructs a valid draw.io XML file with just the frame and axis labels
cat > /home/ga/Diagrams/wardley_map.drawio << 'EOF'
<mxfile host="Electron" modified="2023-10-01T10:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" version="21.6.8" type="device">
  <diagram id="WardleyMapTemplate" name="Page-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Title -->
        <mxCell id="title" value="Cloud Migration Strategy - FintechCo Q3 2025" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=24;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="180" y="20" width="490" height="40" as="geometry" />
        </mxCell>
        <!-- Axes Frame -->
        <mxCell id="axis-y" value="" style="endArrow=classic;html=1;strokeWidth=2;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="80" y="600" as="sourcePoint" />
            <mxPoint x="80" y="80" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="axis-x" value="" style="endArrow=classic;html=1;strokeWidth=2;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="80" y="600" as="sourcePoint" />
            <mxPoint x="800" y="600" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Y-Axis Label -->
        <mxCell id="label-y" value="Value Chain" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;rotation=-90;fontSize=14;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="20" y="320" width="100" height="30" as="geometry" />
        </mxCell>
        <mxCell id="label-vis" value="Visible" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="30" y="80" width="60" height="30" as="geometry" />
        </mxCell>
        <mxCell id="label-invis" value="Invisible" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;" vertex="1" parent="1">
          <mxGeometry x="20" y="570" width="70" height="30" as="geometry" />
        </mxCell>
        <!-- X-Axis Labels & Dividers -->
        <mxCell id="label-gen" value="Genesis" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="120" y="610" width="70" height="30" as="geometry" />
        </mxCell>
        <mxCell id="label-cust" value="Custom Built" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="280" y="610" width="90" height="30" as="geometry" />
        </mxCell>
        <mxCell id="label-prod" value="Product (+Rental)" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="460" y="610" width="110" height="30" as="geometry" />
        </mxCell>
        <mxCell id="label-comm" value="Commodity (+Utility)" style="text;html=1;align=center;verticalAlign=middle;resizable=0;points=[];autosize=1;strokeColor=none;fillColor=none;fontSize=12;" vertex="1" parent="1">
          <mxGeometry x="640" y="610" width="130" height="30" as="geometry" />
        </mxCell>
        <!-- Vertical Dotted Lines -->
        <mxCell id="div-1" value="" style="endArrow=none;dashed=1;html=1;strokeColor=#B3B3B3;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="260" y="600" as="sourcePoint" />
            <mxPoint x="260" y="80" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="div-2" value="" style="endArrow=none;dashed=1;html=1;strokeColor=#B3B3B3;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="440" y="600" as="sourcePoint" />
            <mxPoint x="440" y="80" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="div-3" value="" style="endArrow=none;dashed=1;html=1;strokeColor=#B3B3B3;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="620" y="600" as="sourcePoint" />
            <mxPoint x="620" y="80" as="targetPoint" />
          </mxGeometry>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# Set permissions
chown -R ga:ga /home/ga/Diagrams /home/ga/Desktop
chmod 644 /home/ga/Diagrams/wardley_map.drawio /home/ga/Desktop/cloud_migration_strategy.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial shape count (axes + title + labels ~15 items)
grep -o '<mxCell' /home/ga/Diagrams/wardley_map.drawio | wc -l > /tmp/initial_shape_count.txt

# Launch draw.io
echo "Launching draw.io..."
if ! pgrep -f "drawio" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/wardley_map.drawio &"
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss Update Dialogs (Aggressive)
sleep 5
for i in {1..5}; do
    if DISPLAY=:1 wmctrl -l | grep -i "update"; then
        DISPLAY=:1 xdotool key Escape
    fi
    # Also blind Escape just in case
    DISPLAY=:1 xdotool key Escape
    sleep 1
done

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="