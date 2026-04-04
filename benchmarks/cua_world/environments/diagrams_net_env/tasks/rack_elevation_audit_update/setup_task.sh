#!/bin/bash
set -e
echo "=== Setting up Rack Elevation Audit Update Task ==="

# Source task utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Prepare Directories
su - ga -c "mkdir -p /home/ga/Diagrams/exports"
su - ga -c "mkdir -p /home/ga/Desktop"

# 2. Clean previous run artifacts
rm -f /home/ga/Diagrams/rack_a07.drawio 2>/dev/null || true
rm -f /home/ga/Diagrams/exports/rack_a07_audit.pdf 2>/dev/null || true
rm -f /home/ga/Desktop/rack_a07_changes.txt 2>/dev/null || true

# 3. Create the Initial Rack Diagram (XML)
# This represents the "Old" state before changes
cat > /home/ga/Diagrams/rack_a07.drawio << 'DRAWIO_EOF'
<mxfile host="app.diagrams.net" modified="2024-06-15T10:00:00.000Z" agent="draw.io" version="24.0.0" type="device">
  <diagram id="rack-page1" name="Rack A-07 Front View">
    <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="1654" math="0" shadow="0">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        <mxCell id="rack-frame" value="Rack A-07 (42U)" style="shape=mxgraph.rack.rack;whiteSpace=wrap;container=1;collapsible=0;childLayout=rack;rackLayout=0;rackUnits=42;unitSize=15;unitFirstCharacter=U;currentUnit=0;unitPrefix=U;mountableUnitSize=30;fillColor=#dedad8;strokeColor=#36393d;" vertex="1" parent="1">
          <mxGeometry x="200" y="30" width="200" height="660" as="geometry"/>
        </mxCell>
        <mxCell id="ups-01" value="APC SUA3000RM2U&#xa;UPS-A07-01" style="shape=mxgraph.rack.cisco.cisco_ups;whiteSpace=wrap;fillColor=#f8cecc;strokeColor=#b85450;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="0" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="pdu-01" value="APC AP7920 PDU&#xa;PDU-A07-01" style="shape=mxgraph.rack.2u_rackmount;whiteSpace=wrap;fillColor=#f8cecc;strokeColor=#b85450;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="30" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="spacer-1" value="" style="shape=mxgraph.rack.2u_spacer;whiteSpace=wrap;fillColor=#f5f5f5;strokeColor=#666666;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="60" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="db-primary" value="Dell PowerEdge R640&#xa;DB-PRIMARY-01&#xa;10.1.7.10" style="shape=mxgraph.rack.dell.dell_poweredge_702x;whiteSpace=wrap;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="90" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="db-replica" value="Dell PowerEdge R640&#xa;DB-REPLICA-01&#xa;10.1.7.11" style="shape=mxgraph.rack.dell.dell_poweredge_702x;whiteSpace=wrap;fillColor=#fff2cc;strokeColor=#d6b656;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="120" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="spacer-2" value="" style="shape=mxgraph.rack.2u_spacer;whiteSpace=wrap;fillColor=#f5f5f5;strokeColor=#666666;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="150" width="200" height="60" as="geometry"/>
        </mxCell>
        <mxCell id="sw-core" value="Cisco Catalyst 9300-48P&#xa;SW-CORE-01&#xa;10.1.7.1" style="shape=mxgraph.rack.cisco.cisco_catalyst_702x_series;whiteSpace=wrap;fillColor=#dae8fc;strokeColor=#6c8ebf;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="210" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="spacer-3" value="" style="shape=mxgraph.rack.2u_spacer;whiteSpace=wrap;fillColor=#f5f5f5;strokeColor=#666666;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="240" width="200" height="45" as="geometry"/>
        </mxCell>
        <mxCell id="app-web-01" value="Dell PowerEdge R740&#xa;APP-WEB-01&#xa;10.1.7.20" style="shape=mxgraph.rack.dell.dell_poweredge_702x;whiteSpace=wrap;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="285" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="app-web-02" value="Dell PowerEdge R740&#xa;APP-WEB-02&#xa;10.1.7.21" style="shape=mxgraph.rack.dell.dell_poweredge_702x;whiteSpace=wrap;fillColor=#d5e8d4;strokeColor=#82b366;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="315" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="spacer-4" value="" style="shape=mxgraph.rack.2u_spacer;whiteSpace=wrap;fillColor=#f5f5f5;strokeColor=#666666;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="345" width="200" height="90" as="geometry"/>
        </mxCell>
        <mxCell id="cable-mgmt" value="Cable Management Panel" style="shape=mxgraph.rack.1u_rackmount;whiteSpace=wrap;fillColor=#e6d0de;strokeColor=#996185;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="435" width="200" height="15" as="geometry"/>
        </mxCell>
        <mxCell id="spacer-5" value="" style="shape=mxgraph.rack.2u_spacer;whiteSpace=wrap;fillColor=#f5f5f5;strokeColor=#666666;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="450" width="200" height="135" as="geometry"/>
        </mxCell>
        <mxCell id="pdu-02" value="APC AP7920 PDU&#xa;PDU-A07-02" style="shape=mxgraph.rack.2u_rackmount;whiteSpace=wrap;fillColor=#f8cecc;strokeColor=#b85450;" vertex="1" parent="rack-frame">
          <mxGeometry x="0" y="585" width="200" height="30" as="geometry"/>
        </mxCell>
        <mxCell id="title-block" value="Rack A-07 — Primary Data Center, Row A, Position 7&#xa;Last Updated: 2024-06-15&#xa;Engineer: J. Martinez" style="text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=top;whiteSpace=wrap;overflow=hidden;fontSize=11;" vertex="1" parent="1">
          <mxGeometry x="200" y="700" width="300" height="60" as="geometry"/>
        </mxCell>
        <mxCell id="legend" value="LEGEND (outdated)&#xa;Yellow = Database&#xa;Blue = Network&#xa;Green = Application&#xa;Pink = Power" style="text;html=1;strokeColor=#666666;fillColor=#f5f5f5;align=left;verticalAlign=top;whiteSpace=wrap;overflow=hidden;fontSize=10;rounded=1;" vertex="1" parent="1">
          <mxGeometry x="450" y="30" width="160" height="90" as="geometry"/>
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
DRAWIO_EOF

chown ga:ga /home/ga/Diagrams/rack_a07.drawio
chmod 644 /home/ga/Diagrams/rack_a07.drawio

# 4. Create the Change Log
cat > /home/ga/Desktop/rack_a07_changes.txt << 'CHANGES_EOF'
================================================================
  RACK A-07 — HARDWARE CHANGE LOG FOR AUDIT UPDATE
  Date: 2024-12-20
================================================================

INSTRUCTIONS:
  Update '~/Diagrams/rack_a07.drawio' to reflect these physical changes.

1. REMOVE:
   - Server: DB-REPLICA-01 (was at U9-U10)
   - Reason: Decommissioned

2. ADD NEW HARDWARE:
   - U11-U12: Dell PowerEdge R760 (2U) -> Hostname: DB-REPLICA-02 (Color: ORANGE)
   - U14:     48-Port Patch Panel (1U) -> Hostname: PP-A07-01 (Color: BLUE)
   - U17-U18: Cisco Nexus 93180YC-FX3 (2U) -> Hostname: SW-DIST-01 (Color: BLUE)
   - U24-U25: Dell PowerEdge R660 (2U) -> Hostname: APP-API-01 (Color: GREEN)
   - U26-U27: Dell PowerEdge R660 (2U) -> Hostname: APP-API-02 (Color: GREEN)

3. RELOCATE:
   - Cable Management Panel: Move from U30 to U19

4. AUDIT COLOR-CODING (Apply to ALL items):
   - RED (#f8cecc): Power (UPS, PDU)
   - BLUE (#dae8fc): Network (Switches, Patch Panels)
   - GREEN (#d5e8d4): Compute/App Servers (APP-*)
   - ORANGE (#ffe6cc): Database Servers (DB-*)

5. NEW PAGE: POWER BUDGET
   - Create Page 2 titled "Power Budget"
   - Add a table summarizing rated power:
     * UPS-A07-01: 3000W
     * DB-PRIMARY-01: 750W
     * DB-REPLICA-02: 800W
     * SW-CORE-01: 490W
     * SW-DIST-01: 650W
     * APP-WEB-01/02: 750W each
     * APP-API-01/02: 700W each
     * Patch Panels/PDUs: 0W
   - Calculate Total.

6. EXPORT:
   - Save diagram.
   - Export entire diagram (2 pages) to PDF: ~/Diagrams/exports/rack_a07_audit.pdf
================================================================
CHANGES_EOF
chown ga:ga /home/ga/Desktop/rack_a07_changes.txt
chmod 644 /home/ga/Desktop/rack_a07_changes.txt

# 5. Launch Application
echo "Launching draw.io..."
pkill -f "drawio" 2>/dev/null || true
sleep 1

# Launch with the file
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/rack_a07.drawio > /tmp/drawio.log 2>&1 &"

# Wait for window and dismiss update dialogs
sleep 5
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then
        break
    fi
    sleep 1
done

# Dismiss update dialog (Escape or Tab-Enter)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "rack_a07" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Record Initial State
date +%s > /tmp/task_start_time.txt
stat --format=%Y /home/ga/Diagrams/rack_a07.drawio > /tmp/initial_file_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_file_mtime.txt

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="