#!/bin/bash
set -e
echo "=== Setting up Tech Radar Review Task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 1. Create the Tech Radar Template (XML)
TEMPLATE_FILE="/home/ga/Diagrams/tech_radar_template.drawio"
cat > "$TEMPLATE_FILE" << 'EOF'
<mxfile host="Electron" modified="2024-10-01T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/24.7.5 Chrome/128.0.6613.36 Electron/32.0.1 Safari/537.36" etag="sfw" version="24.7.5" type="device">
  <diagram id="radar-template-1" name="Page-1">
    <mxGraphModel dx="1422" dy="868" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Title -->
        <mxCell id="title" value="Engineering Technology Radar — Q4 2024" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=24;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="220" y="40" width="400" height="40" as="geometry" />
        </mxCell>
        <!-- Quadrant Lines -->
        <mxCell id="line-vert" value="" style="endArrow=none;html=1;rounded=0;strokeWidth=2;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="420" y="120" as="sourcePoint" />
            <mxPoint x="420" y="920" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <mxCell id="line-horiz" value="" style="endArrow=none;html=1;rounded=0;strokeWidth=2;" edge="1" parent="1">
          <mxGeometry width="50" height="50" relative="1" as="geometry">
            <mxPoint x="20" y="520" as="sourcePoint" />
            <mxPoint x="820" y="520" as="targetPoint" />
          </mxGeometry>
        </mxCell>
        <!-- Rings (Hold, Assess, Trial, Adopt) -->
        <mxCell id="ring-hold" value="" style="ellipse;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#666666;dashed=1;" vertex="1" parent="1">
          <mxGeometry x="20" y="120" width="800" height="800" as="geometry" />
        </mxCell>
        <mxCell id="ring-assess" value="" style="ellipse;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#666666;dashed=1;" vertex="1" parent="1">
          <mxGeometry x="120" y="220" width="600" height="600" as="geometry" />
        </mxCell>
        <mxCell id="ring-trial" value="" style="ellipse;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#666666;dashed=1;" vertex="1" parent="1">
          <mxGeometry x="220" y="320" width="400" height="400" as="geometry" />
        </mxCell>
        <mxCell id="ring-adopt" value="" style="ellipse;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#666666;dashed=1;" vertex="1" parent="1">
          <mxGeometry x="320" y="420" width="200" height="200" as="geometry" />
        </mxCell>
        <!-- Ring Labels -->
        <mxCell id="lbl-adopt" value="ADOPT" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontColor=#666666;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="390" y="430" width="60" height="30" as="geometry" />
        </mxCell>
        <mxCell id="lbl-trial" value="TRIAL" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontColor=#666666;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="390" y="330" width="60" height="30" as="geometry" />
        </mxCell>
        <mxCell id="lbl-assess" value="ASSESS" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontColor=#666666;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="390" y="230" width="60" height="30" as="geometry" />
        </mxCell>
        <mxCell id="lbl-hold" value="HOLD" style="text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontColor=#666666;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="390" y="130" width="60" height="30" as="geometry" />
        </mxCell>
        <!-- Quadrant Labels -->
        <mxCell id="quad-tl" value="Languages &amp; Frameworks" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="30" y="90" width="250" height="30" as="geometry" />
        </mxCell>
        <mxCell id="quad-tr" value="Techniques" style="text;html=1;strokeColor=none;fillColor=none;align=right;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="570" y="90" width="250" height="30" as="geometry" />
        </mxCell>
        <mxCell id="quad-bl" value="Platforms" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="30" y="930" width="250" height="30" as="geometry" />
        </mxCell>
        <mxCell id="quad-br" value="Tools" style="text;html=1;strokeColor=none;fillColor=none;align=right;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=16;fontStyle=1" vertex="1" parent="1">
          <mxGeometry x="570" y="930" width="250" height="30" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF
chown ga:ga "$TEMPLATE_FILE"

# 2. Create the Assessment Data File
DATA_FILE="/home/ga/Desktop/tech_assessment_Q4_2024.txt"
cat > "$DATA_FILE" << 'EOF'
ENGINEERING TECHNOLOGY RADAR - Q4 2024 ASSESSMENT
=================================================

Format: Technology Name | Quadrant | Ring | Movement

TECHNIQUES
----------
Retrieval Augmented Generation (RAG) | Techniques | Trial | New
Platform Engineering                 | Techniques | Adopt | Moved In
Continuous Compliance                | Techniques | Trial | Moved In
Design Tokens                        | Techniques | Assess | New
Long-lived Feature Branches          | Techniques | Hold | Moved Out

TOOLS
-----
Renovate                   | Tools | Adopt | Moved In
GitHub Actions             | Tools | Adopt | No Change
Backstage                  | Tools | Trial | New
dbt                        | Tools | Trial | No Change
Terraform Cloud            | Tools | Hold | Moved Out

PLATFORMS
---------
Kubernetes                 | Platforms | Adopt | No Change
Cloudflare Workers         | Platforms | Adopt | Moved In
Databricks Unity Catalog   | Platforms | Trial | New
Fly.io                     | Platforms | Assess | No Change
Azure DevOps               | Platforms | Hold | Moved Out

LANGUAGES & FRAMEWORKS
-----------------------
TypeScript    | Languages & Frameworks | Adopt | No Change
Rust          | Languages & Frameworks | Trial | Moved In
htmx          | Languages & Frameworks | Trial | New
LangChain     | Languages & Frameworks | Assess | New
Mojo          | Languages & Frameworks | Assess | New

COLOR CODE KEY:
- New: Green (#00CC00)
- Moved In: Blue (#3399FF)
- Moved Out: Orange (#FF9900)
- No Change: Gray (#CCCCCC)
EOF
chown ga:ga "$DATA_FILE"

# 3. Clean previous results
rm -f /home/ga/Diagrams/tech_radar_Q4_2024.drawio
rm -f /home/ga/Diagrams/exports/tech_radar_Q4_2024.png
rm -f /tmp/task_result.json

# 4. Record baseline state
grep -c "<mxCell" "$TEMPLATE_FILE" > /tmp/initial_shape_count.txt

# 5. Launch Application
if ! pgrep -f "drawio" > /dev/null; then
    echo "Starting draw.io..."
    # Launch with the template file
    su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox '$TEMPLATE_FILE' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
            echo "draw.io window detected"
            break
        fi
        sleep 1
    done
fi

# 6. Aggressively dismiss update dialog
# This is a common issue with the AppImage; we try multiple methods
echo "Attempting to dismiss update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Try clicking the "Cancel" button area (approximate)
    # DISPLAY=:1 xdotool mousemove 1100 600 click 1 2>/dev/null || true
done

# 7. Maximize and Focus
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "draw.io" 2>/dev/null || true

# 8. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="