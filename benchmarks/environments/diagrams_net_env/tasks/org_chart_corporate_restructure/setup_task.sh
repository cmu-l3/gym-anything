#!/bin/bash
set -e

echo "=== Setting up Org Chart Restructuring Task ==="

# Ensure directories exist
su - ga -c "mkdir -p /home/ga/Diagrams/exports /home/ga/Desktop" 2>/dev/null || true

# 1. Create the Initial Org Chart (.drawio XML)
# This represents the "Before" state: 16 people, default white styling
cat > /home/ga/Diagrams/org_chart.drawio << 'EOF'
<mxfile host="Electron" modified="2024-05-20T10:00:00.000Z" agent="Mozilla/5.0" version="24.4.0" type="device">
  <diagram id="org_chart_1" name="Page-1">
    <mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- CEO -->
        <mxCell id="ceo" value="Sarah Chen&#xa;CEO" style="rounded=1;whiteSpace=wrap;html=1;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="360" y="40" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- VP Level -->
        <mxCell id="vp_eng" value="Michael Torres&#xa;VP Engineering" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="vp_mkt" value="David Brown&#xa;VP Marketing" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="200" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="vp_sales" value="Jennifer Lee&#xa;VP Sales" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="360" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="vp_ops" value="Thomas Anderson&#xa;VP Operations" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="520" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="cfo" value="Patricia Johnson&#xa;CFO" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="680" y="160" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- Connections CEO -> VPs -->
        <mxCell id="e1" edge="1" parent="1" source="ceo" target="vp_eng"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e2" edge="1" parent="1" source="ceo" target="vp_mkt"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e3" edge="1" parent="1" source="ceo" target="vp_sales"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e4" edge="1" parent="1" source="ceo" target="vp_ops"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e5" edge="1" parent="1" source="ceo" target="cfo"><mxGeometry relative="1" as="geometry"/></mxCell>

        <!-- Engineering Dept -->
        <mxCell id="dir_fe" value="Lisa Park&#xa;Dir. Frontend" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="10" y="280" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="dir_be" value="James Wilson&#xa;Dir. Backend" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="120" y="280" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="dir_qa" value="Rachel Kim&#xa;Dir. QA" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="65" y="340" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="e_eng1" edge="1" parent="1" source="vp_eng" target="dir_fe"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e_eng2" edge="1" parent="1" source="vp_eng" target="dir_be"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e_eng3" edge="1" parent="1" source="vp_eng" target="dir_qa"><mxGeometry relative="1" as="geometry"/></mxCell>

        <!-- Marketing Dept -->
        <mxCell id="dir_dm" value="Emily Davis&#xa;Dir. Digital Marketing" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="210" y="280" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="dir_brand" value="Chris Taylor&#xa;Dir. Brand" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="210" y="340" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="e_mkt1" edge="1" parent="1" source="vp_mkt" target="dir_dm"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e_mkt2" edge="1" parent="1" source="vp_mkt" target="dir_brand"><mxGeometry relative="1" as="geometry"/></mxCell>

        <!-- Sales Dept -->
        <mxCell id="dir_ent" value="Robert Garcia&#xa;Dir. Enterprise Sales" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="370" y="280" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="dir_smb" value="Amanda White&#xa;Dir. SMB Sales" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="370" y="340" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="e_sales1" edge="1" parent="1" source="vp_sales" target="dir_ent"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e_sales2" edge="1" parent="1" source="vp_sales" target="dir_smb"><mxGeometry relative="1" as="geometry"/></mxCell>

        <!-- Ops Dept -->
        <mxCell id="dir_it" value="Kevin Martinez&#xa;Dir. IT" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="530" y="280" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="dir_fac" value="Susan Clark&#xa;Dir. Facilities" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="530" y="340" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="e_ops1" edge="1" parent="1" source="vp_ops" target="dir_it"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e_ops2" edge="1" parent="1" source="vp_ops" target="dir_fac"><mxGeometry relative="1" as="geometry"/></mxCell>

        <!-- Finance Dept -->
        <mxCell id="dir_acct" value="Mark Robinson&#xa;Dir. Accounting" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="690" y="280" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="dir_fpa" value="Laura Thompson&#xa;Dir. FP&amp;A" style="rounded=1;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="690" y="340" width="100" height="50" as="geometry" />
        </mxCell>
        <mxCell id="e_fin1" edge="1" parent="1" source="cfo" target="dir_acct"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e_fin2" edge="1" parent="1" source="cfo" target="dir_fpa"><mxGeometry relative="1" as="geometry"/></mxCell>

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF
chown ga:ga /home/ga/Diagrams/org_chart.drawio
chmod 644 /home/ga/Diagrams/org_chart.drawio

# 2. Create the Restructuring Memo
cat > /home/ga/Desktop/restructuring_memo.txt << 'EOF'
MEMORANDUM
TO: HR Business Partner
FROM: Chief of Staff, TechNova Inc.
DATE: 2024-05-20
SUBJECT: Q3 Corporate Restructuring & Org Chart Updates

Please update the official organizational chart (org_chart.drawio) immediately to reflect the following strategic changes approved by the board.

CHANGES REQUIRED:

1. EXECUTIVE PROMOTION: Promote "Michael Torres" from VP Engineering to "CTO" (Chief Technology Officer). He remains a direct report to the CEO.

2. NEW HIRE: We have hired "Maria Santos" as the new "VP Product". Add her as a direct report to the CEO.

3. REORG: Move "Rachel Kim" (currently Dir. QA under Engineering) to the Operations department, reporting to Thomas Anderson. Change her title to "Dir. Quality Assurance".

4. NEW HIRE: Add "Dr. Alex Patel" as "Dir. Data Science" reporting strictly to Michael Torres (CTO).

5. TITLE CHANGE: In Marketing, rename Emily Davis's title to "Dir. Growth Marketing".

6. SALES CONSOLIDATION: We are eliminating the SMB Sales division.
   - Rename "Robert Garcia" to "Dir. Sales Operations".
   - Remove the "Dir. SMB Sales" position (Amanda White has left the organization).

7. NEW EXECUTIVE: We have hired "Hannah Wright" as "CHRO" (Chief Human Resources Officer) reporting to the CEO.

8. SECURITY EXPANSION: Update Kevin Martinez's title to "Dir. IT & Security".

9. COLOR CODING: Apply the following fill colors to the boxes for each department to improve readability:
   - Engineering (CTO & reports): Blue (#DAE8FC)
   - Product (VP & reports): Teal (#D4E1F5)
   - Marketing: Green (#D5E8D4)
   - Sales: Orange (#FFE6CC)
   - Operations: Gray (#F5F5F5)
   - Finance: Purple (#E1D5E7)
   - HR (CHRO): Pink (#F8CECC)
   - CEO: White (Default)

DELIVERABLES:
- Update the .drawio file.
- Export a PNG image to ~/Diagrams/exports/org_chart.png
- Export a PDF document to ~/Diagrams/exports/org_chart.pdf

Thank you for handling this promptly.
EOF
chown ga:ga /home/ga/Desktop/restructuring_memo.txt
chmod 644 /home/ga/Desktop/restructuring_memo.txt

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io with the diagram
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/org_chart.drawio > /tmp/drawio_launch.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Aggressively dismiss update dialog if it appears
# This uses the helper script created in environment setup or mimics it
echo "Attempting to dismiss potential update dialog..."
for i in {1..10}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    # Click common "Cancel" button location (center-ish right)
    DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true
done

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="