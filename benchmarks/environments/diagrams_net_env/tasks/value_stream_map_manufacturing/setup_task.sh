#!/bin/bash
set -e

echo "=== Setting up Value Stream Map Manufacturing Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# 2. Create the Data Sheet
DATA_SHEET="/home/ga/Desktop/vsm_data_sheet.txt"
cat > "$DATA_SHEET" << 'EOF'
═══════════════════════════════════════════════════════════
  ACME STAMPING PLANT — VALUE STREAM MAP DATA COLLECTION
  Product Family: Steering Brackets (LH & RH)
  Date Collected: 2024-11-15
═══════════════════════════════════════════════════════════

CUSTOMER: STATE STREET ASSEMBLY
  - Monthly demand: 18,400 pieces
  - Daily demand: 920 pieces
  - Shipping: 1 truck daily

SUPPLIER: MICHIGAN STEEL CO.
  - Material: Steel coils (500 ft each)
  - Delivery: Tuesdays + Thursdays
  - Lead time: 6 weeks

PRODUCTION CONTROL:
  - Receives 90-day forecast from customer
  - Sends weekly schedule to processes

═══════════════════════════════════════════════════════════
PROCESS STEP DATA (ADD THESE TO DIAGRAM)
═══════════════════════════════════════════════════════════

1. STAMPING (Already in diagram)
   C/T: 1 sec, C/O: 1 hr, Uptime: 85%, Batch: 1,000

2. WELDING I (Already in diagram)
   C/T: 39 sec, C/O: 10 min, Uptime: 100%, Batch: 1

3. WELDING II (MISSING - ADD THIS)
   C/T: 46 sec
   C/O: 10 min
   Uptime: 80%
   Batch: 1

4. ASSEMBLY I (MISSING - ADD THIS)
   C/T: 62 sec
   C/O: 0
   Uptime: 100%

5. ASSEMBLY II (MISSING - ADD THIS)
   C/T: 40 sec
   C/O: 0
   Uptime: 100%

6. SHIPPING (MISSING - ADD THIS)
   Staging area, 1 shipment/day

═══════════════════════════════════════════════════════════
INVENTORY (WIP) TO ADD BETWEEN STEPS
═══════════════════════════════════════════════════════════
- Raw Material: 5 days
- After Stamping: 4,600 pcs (4.6 days)
- After Welding I: 1,100 pcs (1.1 days)
- After Welding II: 1,600 pcs (1.6 days)
- After Assembly I: 1,200 pcs (1.2 days)
- After Assembly II: 2,700 pcs (2.7 days)

═══════════════════════════════════════════════════════════
LEAD TIME LADDER TOTALS
═══════════════════════════════════════════════════════════
- Total Lead Time: 23.5 days
- Total Processing Time: 188 seconds

═══════════════════════════════════════════════════════════
FUTURE STATE REQUIREMENTS (PAGE 2)
═══════════════════════════════════════════════════════════
1. Combine Welding I + II into "Weld Cell"
2. Combine Assembly I + II into "Assembly Cell"
3. Add Supermarket between Stamping and Weld Cell
4. Add FIFO lane between Weld and Assembly
5. Add Kaizen bursts for improvements
EOF

# 3. Create the Partial .drawio File
# This XML mimics a partially drawn VSM
DIAGRAM_FILE="/home/ga/Diagrams/stamping_vsm.drawio"
cat > "$DIAGRAM_FILE" << 'XMLEOF'
<mxfile host="Electron" modified="2024-02-01T10:00:00.000Z" agent="Mozilla/5.0" version="22.1.0" type="device">
  <diagram name="Current State" id="page1">
    <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1100" pageHeight="850" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="supp" value="Michigan Steel Co." style="shape=mxgraph.lean_mapping.outside_sources;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="100" height="60" as="geometry" />
        </mxCell>
        <mxCell id="cust" value="State Street Assembly" style="shape=mxgraph.lean_mapping.outside_sources;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="900" y="40" width="100" height="60" as="geometry" />
        </mxCell>
        <mxCell id="pc" value="Production Control" style="shape=process;whiteSpace=wrap;html=1;backgroundOutline=1;" vertex="1" parent="1">
          <mxGeometry x="450" y="40" width="160" height="60" as="geometry" />
        </mxCell>
        <mxCell id="proc1" value="Stamping" style="shape=process;whiteSpace=wrap;html=1;backgroundOutline=1;" vertex="1" parent="1">
          <mxGeometry x="120" y="240" width="100" height="60" as="geometry" />
        </mxCell>
        <mxCell id="data1" value="C/T: 1 sec&#xa;C/O: 1 hr&#xa;Uptime: 85%" style="text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;strokeWidth=1;strokeColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="120" y="310" width="100" height="60" as="geometry" />
        </mxCell>
        <mxCell id="proc2" value="Welding I" style="shape=process;whiteSpace=wrap;html=1;backgroundOutline=1;" vertex="1" parent="1">
          <mxGeometry x="300" y="240" width="100" height="60" as="geometry" />
        </mxCell>
        <mxCell id="data2" value="C/T: 39 sec&#xa;C/O: 10 min&#xa;Uptime: 100%" style="text;html=1;align=left;verticalAlign=top;whiteSpace=wrap;rounded=0;strokeWidth=1;strokeColor=#000000;" vertex="1" parent="1">
          <mxGeometry x="300" y="310" width="100" height="60" as="geometry" />
        </mxCell>
        <mxCell id="arrow1" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;" edge="1" parent="1" source="pc" target="supp">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XMLEOF

# Set permissions
chown ga:ga "$DATA_SHEET" "$DIAGRAM_FILE"
chmod 644 "$DATA_SHEET" "$DIAGRAM_FILE"

# 4. Record Timestamp & Initial State
date +%s > /tmp/task_start_time.txt
grep -c "<mxCell" "$DIAGRAM_FILE" > /tmp/initial_cell_count.txt

# 5. Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox '$DIAGRAM_FILE' > /dev/null 2>&1 &"

# 6. Handle Update Dialog (Aggressive Dismissal)
echo "Handling potential update dialogs..."
sleep 5
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "update|confirm"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    else
        # If draw.io main window is active, break
        if DISPLAY=:1 wmctrl -l | grep -q "stamping_vsm.drawio"; then
            break
        fi
    fi
    sleep 1
done
# Safety escape sequences
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. Maximize Window
sleep 2
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="