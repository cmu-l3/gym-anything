#!/bin/bash
set -e

echo "=== Setting up UBO Beneficial Ownership Map task ==="

# 1. Create Directories
mkdir -p /home/ga/Diagrams/exports
mkdir -p /home/ga/Desktop

# 2. Create the Investigation Report
cat > /home/ga/Desktop/investigation_report_882.txt << 'EOF'
CONFIDENTIAL - FINANCIAL INTELLIGENCE UNIT
INVESTIGATION REPORT #882-KYC
SUBJECT: OMNIVERSE LOGISTICS LTD.
DATE: 2023-10-14

EXECUTIVE SUMMARY:
We have received corporate registry documents for OmniVerse Logistics. The structure appears to be a "Complex Control Structure" designed to obscure ultimate beneficiaries.

OWNERSHIP DATA:
1. TARGET ENTITY: OmniVerse Logistics Ltd.
   - Shareholder A: Stratosphere Holdings (owns 60% of OmniVerse)
   - Shareholder B: Terra Firma Ventures (owns 40% of OmniVerse)

2. INTERMEDIARY: Stratosphere Holdings
   - Shareholder A: Elena R. (owns 30% of Stratosphere)
   - Shareholder B: Nebula Trust (owns 70% of Stratosphere)

3. INTERMEDIARY: Terra Firma Ventures
   - Shareholder A: Elena R. (owns 50% of Terra Firma)
   - Shareholder B: Marcus T. (owns 50% of Terra Firma)

4. TRUST ARRANGEMENT: Nebula Trust
   - The trust deed identifies the sole beneficiary as Marcus T. (100% beneficiary interest).

TASK:
Map this structure. Calculate effective ownership for Elena R. and Marcus T.
Apply FATF "25% Rule" to identify UBOs.
- UBOs (>25% effective interest) must be highlighted in RED.
- Non-UBOs (<=25%) must be highlighted in GREEN.
EOF

# 3. Create the Starter Diagram (XML)
# Contains just the main entity "OmniVerse Logistics"
cat > /home/ga/Diagrams/omniverse_structure.drawio << 'EOF'
<mxfile host="Electron" modified="2023-10-15T10:00:00.000Z" agent="Mozilla/5.0" version="21.6.8" type="device">
  <diagram name="Ownership Structure" id="ubo-diagram-1">
    <mxGraphModel dx="1422" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="850" pageHeight="1100" math="0" shadow="0">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="target-entity" value="OmniVerse Logistics" style="rounded=0;whiteSpace=wrap;html=1;fontStyle=1;fontSize=14;" vertex="1" parent="1">
          <mxGeometry x="360" y="480" width="160" height="80" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
EOF

# 4. Set Permissions
chown -R ga:ga /home/ga/Diagrams
chown -R ga:ga /home/ga/Desktop
chmod 644 /home/ga/Desktop/investigation_report_882.txt
chmod 644 /home/ga/Diagrams/omniverse_structure.drawio

# 5. Launch draw.io
echo "Launching draw.io..."
export DISPLAY=:1
su - ga -c "/opt/drawio/drawio.AppImage --no-sandbox /home/ga/Diagrams/omniverse_structure.drawio" > /tmp/drawio.log 2>&1 &
DRAWIO_PID=$!

# 6. Handle Update Dialogs (Anti-Blocking)
echo "Waiting for draw.io to initialize..."
for i in {1..15}; do
    sleep 1
    # Check for update dialog windows
    if wmctrl -l | grep -i "update"; then
        echo "Dismissing update dialog..."
        xdotool key Escape
        sleep 0.5
    fi
done

# Ensure main window is focused and maximized
sleep 2
wmctrl -a "draw.io" || true
wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz || true

# 7. Record Start Time and Initial State
date +%s > /tmp/task_start_time.txt
md5sum /home/ga/Diagrams/omniverse_structure.drawio > /tmp/initial_hash.txt

# 8. Take Initial Screenshot
scrot /tmp/task_initial.png

echo "=== Setup Complete ==="