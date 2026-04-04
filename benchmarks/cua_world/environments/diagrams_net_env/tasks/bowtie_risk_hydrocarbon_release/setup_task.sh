#!/bin/bash
set -e
echo "=== Setting up Bow-Tie Risk Diagram Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop

# Clean up any previous run artifacts
rm -f /home/ga/Diagrams/bowtie_hydrocarbon_release.drawio
rm -f /home/ga/Diagrams/bowtie_hydrocarbon_release.pdf

# Create the input risk assessment report
cat > /home/ga/Desktop/risk_assessment_report.txt << 'EOF'
OFFSHORE PLATFORM RISK ASSESSMENT REPORT
=========================================
Facility: Deepwater Platform Alpha-7
Date: 2024-11-15
Type: Bow-Tie Analysis & Risk Matrix

TOP EVENT (Central Shape)
-------------------------
Name: Uncontrolled Hydrocarbon Release
Color: Orange (#FF8800)
Shape: Hexagon or Diamond

THREATS (Left Side)
-------------------
Color: Red (#FF4444)
T1: Wellbore Integrity Failure
T2: Process Equipment Failure
T3: Flowline/Riser Damage
T4: Human Error During Operations
T5: Extreme Weather Event

PREVENTION BARRIERS (Between Threats and Top Event)
---------------------------------------------------
Color: Blue (#4488CC)
PB1: Integrity Management Program (Prevents T1)
PB2: Pressure Safety Systems (Prevents T2)
PB3: Subsea Inspection System (Prevents T3)
PB4: Permit-to-Work System (Prevents T4)
PB5: Met-Ocean Monitoring (Prevents T5)

CONSEQUENCES (Right Side)
-------------------------
Color: Dark Red (#CC2222)
C1: Fire/Explosion on Platform
C2: Personnel Casualties
C3: Major Environmental Spill
C4: Asset Damage & Production Loss
C5: Regulatory Enforcement Action

MITIGATION BARRIERS (Between Top Event and Consequences)
--------------------------------------------------------
Color: Green (#44AA44)
MB1: Gas Detection & ESD (Mitigates C1)
MB2: Emergency Response & Muster (Mitigates C2)
MB3: Oil Spill Response Equipment (Mitigates C3)
MB4: Business Continuity Plan (Mitigates C4)
MB5: Incident Investigation (Mitigates C5)

RISK MATRIX (Page 2)
====================
Create a 5x5 Grid:
Rows (Likelihood): Rare, Unlikely, Possible, Likely, Almost Certain
Cols (Severity): Negligible, Minor, Moderate, Major, Catastrophic

Cell Colors:
- Low Risk: Green
- Medium Risk: Yellow
- High Risk: Orange
- Extreme Risk: Red

Plot these Risks:
R1 (High): Unlikely / Catastrophic
R2 (High): Possible / Major
R3 (High): Likely / Moderate
R4 (High): Rare / Catastrophic
R5 (Medium): Unlikely / Major
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/risk_assessment_report.txt
chmod 644 /home/ga/Desktop/risk_assessment_report.txt

# Ensure draw.io is not running initially
pkill -f drawio || true

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Dismiss update dialogs (common in draw.io appimage)
sleep 5
echo "Dismissing potential update dialogs..."
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="