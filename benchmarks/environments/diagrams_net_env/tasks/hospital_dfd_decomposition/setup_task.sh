#!/bin/bash
set -e

echo "=== Setting up Hospital DFD Decomposition Task ==="

# 1. Create Directories
su - ga -c "mkdir -p /home/ga/Diagrams/exports /home/ga/Desktop" 2>/dev/null || true

# 2. Create the Starter Diagram (Context Diagram)
# We construct a valid draw.io XML file with one page containing the context diagram
DIAGRAM_FILE="/home/ga/Diagrams/hospital_dfd.drawio"

cat > "$DIAGRAM_FILE" << 'EOF'
<mxfile host="Electron" modified="2023-10-01T12:00:00.000Z" agent="5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) draw.io/21.6.8 Chrome/114.0.5735.289 Electron/25.5.0 Safari/537.36" etag="WXYZ" version="21.6.8" type="device">
  <diagram name="Context Diagram" id="context-page">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <!-- Central Process -->
        <mxCell id="proc0" value="0 - Patient Management System" style="ellipse;whiteSpace=wrap;html=1;aspect=fixed;" vertex="1" parent="1">
          <mxGeometry x="360" y="360" width="120" height="120" as="geometry" />
        </mxCell>
        <!-- External Entities -->
        <mxCell id="ext1" value="Patient" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="360" y="160" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="ext2" value="Insurance Company" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="640" y="390" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="ext3" value="Physician" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="80" y="390" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="ext4" value="Pharmacy" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="200" y="600" width="120" height="60" as="geometry" />
        </mxCell>
        <mxCell id="ext5" value="Laboratory" style="rounded=0;whiteSpace=wrap;html=1;" vertex="1" parent="1">
          <mxGeometry x="520" y="600" width="120" height="60" as="geometry" />
        </mxCell>
        <!-- Edges -->
        <mxCell id="edge1" value="Registration Info" style="endArrow=classic;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="ext1" target="proc0">
          <mxGeometry width="50" height="50" relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

chown ga:ga "$DIAGRAM_FILE"
chmod 644 "$DIAGRAM_FILE"

# 3. Create the Specification Document
SPEC_FILE="/home/ga/Desktop/patient_system_spec.txt"

cat > "$SPEC_FILE" << 'EOF'
HOSPITAL PATIENT MANAGEMENT SYSTEM - SYSTEM SPECIFICATION

1.0 LEVEL-0 DFD REQUIREMENTS
The system shall be decomposed into the following 5 main processes:

Process 1.0: Patient Registration
- Inputs: Registration Info (from Patient)
- Outputs: Patient Details (to Process 2.0 and 4.0)
- Data Store: D1 - Patient Records

Process 2.0: Appointment Scheduling
- Inputs: Schedule Request (from Patient), Availability (from Physician)
- Outputs: Appointment Confirmation (to Patient)
- Data Store: D2 - Appointment Log

Process 3.0: Clinical Documentation
- Inputs: Diagnosis (from Physician), Lab Results (from Laboratory)
- Outputs: Lab Orders (to Laboratory), Prescriptions (to Process 5.0)
- Data Store: D3 - Clinical Notes

Process 4.0: Billing and Claims
- Inputs: Charge Data (from Process 3.0), Patient Details (from Process 1.0)
- Outputs: Claims (to Insurance Company), Bills (to Patient)
- Data Store: D4 - Billing Records

Process 5.0: Pharmacy Management
- Inputs: Prescriptions (from Process 3.0), Inventory Data (from Pharmacy entity)
- Outputs: Dispensing Info (to Patient)
- Data Store: D5 - Prescription Database

2.0 LEVEL-1 DFD REQUIREMENTS (BILLING SUBSYSTEM)
Decompose Process 4.0 into the following sub-processes:

Process 4.1: Charge Capture
- Retrieves rates from D4.1 - Charge Master
- Receives clinical codes from Clinical Documentation

Process 4.2: Claims Generation
- Generates CMS-1500/UB-04 claims
- Logs claims in D4.2 - Claims Log
- Sends claims to Insurance Company

Process 4.3: Payment Processing
- Receives ERA/EOB from Insurance Company
- Receives Co-pays from Patient
- Updates D4.3 - Payment Ledger

Process 4.4: Denial Management
- Reviews denied claims from D4.2
- Resubmits corrected claims

3.0 GENERAL DIAGRAMMING RULES
- Use standard Yourdon-DeMarco or Gane-Sarson notation.
- Label all data flows.
- Maintain consistency with the Context Diagram.
EOF

chown ga:ga "$SPEC_FILE"
chmod 644 "$SPEC_FILE"

# 4. Record Initial State
echo "1" > /tmp/initial_page_count
# Count lines in XML as a proxy for complexity
wc -l < "$DIAGRAM_FILE" > /tmp/initial_xml_lines

# 5. Launch draw.io
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 1

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox '$DIAGRAM_FILE' > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Dismiss Update Dialog (Aggressive)
sleep 5
echo "Dismissing update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
done
# Try clicking "Cancel" button blind spot (approx coordinates)
DISPLAY=:1 xdotool mousemove 1050 580 click 1 2>/dev/null || true

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Record timestamp
date +%s > /tmp/task_start_time.txt

# 7. Take screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="