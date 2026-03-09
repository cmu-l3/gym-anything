#!/bin/bash
set -e

echo "=== Setting up ICS Purdue Model Segmentation Task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Device Inventory Text File
cat > /home/ga/Desktop/device_inventory.txt << 'EOF'
=== DEVICE INVENTORY & FUNCTION LIST ===

1. Corporate ERP Server
   - Function: SAP System for finance and HR
   - Zone: Corporate Network (Enterprise)

2. Corporate Email Server
   - Function: Microsoft Exchange
   - Zone: Corporate Network (Enterprise)

3. Secure Jump Host
   - Function: VPN landing point for remote vendors
   - Zone: Demilitarized Zone (DMZ)

4. Plant Historian
   - Function: Long-term storage of process data (OSIsoft PI)
   - Zone: Manufacturing Operations (MOM)

5. MES Server
   - Function: Manufacturing Execution System, tracks work orders
   - Zone: Manufacturing Operations (MOM)

6. Main HMI
   - Function: Control room operator interface
   - Zone: Supervisory Control

7. SCADA Master
   - Function: Ignition Gateway, central control server
   - Zone: Supervisory Control

8. Assembly Line PLC
   - Function: Siemens S7-1500 controlling conveyor motors
   - Zone: Basic Control / Field

9. Safety Controller
   - Function: Dedicated safety shutdown system
   - Zone: Basic Control / Field

10. Robot Controller
    - Function: Fanuc arm controller
    - Zone: Basic Control / Field

11. VFD Pump Drive
    - Function: Variable Frequency Drive for cooling pumps
    - Zone: Basic Control / Field
EOF

# 3. Generate the "Messy" .drawio XML File
# We construct a valid XML with unparented shapes scattered randomly
cat > /home/ga/Diagrams/factory_audit.drawio << 'XML_EOF'
<mxfile host="Electron" modified="2024-03-01T12:00:00.000Z" agent="Mozilla/5.0" version="22.1.2" type="device">
  <diagram id="SyZ0" name="Page-1">
    <mxGraphModel dx="1422" dy="794" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        
        <!-- Central Unmanaged Switch (Problematic) -->
        <mxCell id="switch1" value="Unmanaged Switch" style="image;html=1;image=img/lib/clip_art/networking/Switch_128x128.png" vertex="1" parent="1">
          <mxGeometry x="350" y="350" width="80" height="80" as="geometry" />
        </mxCell>

        <!-- Level 4 Devices -->
        <mxCell id="d1" value="Corporate ERP" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
          <mxGeometry x="50" y="50" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="d2" value="Email Server" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="1">
          <mxGeometry x="200" y="80" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- DMZ Devices -->
        <mxCell id="d3" value="Jump Host" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;" vertex="1" parent="1">
          <mxGeometry x="600" y="100" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- Level 3 Devices -->
        <mxCell id="d4" value="Plant Historian" style="shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=15;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="1">
          <mxGeometry x="100" y="500" width="60" height="80" as="geometry" />
        </mxCell>
        <mxCell id="d5" value="MES Server" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="1">
          <mxGeometry x="200" y="550" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- Level 2 Devices -->
        <mxCell id="d6" value="Main HMI" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="600" y="400" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="d7" value="SCADA Master" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="1">
          <mxGeometry x="450" y="450" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- Level 1 Devices -->
        <mxCell id="d8" value="Assembly Line PLC" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="50" y="700" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="d9" value="Safety Controller" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="200" y="720" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="d10" value="Robot Controller" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="350" y="680" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="d11" value="VFD Pump" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;" vertex="1" parent="1">
          <mxGeometry x="500" y="700" width="120" height="60" as="geometry" />
        </mxCell>

        <!-- Messy Connections -->
        <mxCell id="e1" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d1" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e2" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d2" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e3" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d3" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e4" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d4" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e5" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d6" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e6" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d8" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>
        <mxCell id="e7" value="" style="endArrow=none;html=1;" edge="1" parent="1" source="d10" target="switch1"><mxGeometry relative="1" as="geometry"/></mxCell>

      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
XML_EOF

chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop
chmod 644 /home/ga/Diagrams/factory_audit.drawio
chmod 644 /home/ga/Desktop/device_inventory.txt

# 4. Anti-gaming Timestamp
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_pdf_size

# 5. Launch Application
echo "Launching draw.io..."
pkill -f drawio 2>/dev/null || true
su - ga -c "DISPLAY=:1 /usr/local/bin/drawio /home/ga/Diagrams/factory_audit.drawio > /dev/null 2>&1 &"

# 6. Wait for Window and Maximize
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io" | grep -v "grep"; then
        echo "Window found."
        break
    fi
    sleep 1
done

sleep 3
# Attempt to maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Dismiss Updates (Critical for draw.io)
echo "Dismissing potential update dialog..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 8. Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="