#!/bin/bash
set -e
echo "=== Setting up PERT/CPM Construction Schedule task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Diagrams
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Diagrams /home/ga/Desktop

# Create the WBS CSV data file
# Data based on standard construction scheduling examples
cat > /home/ga/Desktop/construction_wbs.csv << 'CSVEOF'
ID,Activity,Duration_Days,Predecessors
A,Site Preparation,4,
B,Foundation,6,A
C,Underground Plumbing,3,B
D,Concrete Slab,2,C
E,Framing,10,D
F,Roofing,5,E
G,Windows and Doors,3,F
H,Exterior Finishing,7,G
I,Rough Electrical,5,E
J,Rough Interior Plumbing,4,E
K,Rough HVAC,5,E
L,Insulation,3,"G,I,J,K"
M,Drywall,6,L
N,Interior Painting,4,M
O,Finish Electrical and Plumbing,4,N
P,Flooring Installation,5,O
Q,Cabinetry and Final Trim,4,P
R,Final Inspection,2,"Q,H"
CSVEOF
chown ga:ga /home/ga/Desktop/construction_wbs.csv

# Create a brief instruction supplement on the desktop
cat > /home/ga/Desktop/pert_instructions.txt << 'INSTEOF'
PERT/CPM Network Diagram Requirements
======================================

1. DATA SOURCE: Use construction_wbs.csv on Desktop.

2. NODE FORMAT:
   Create a box for each activity containing:
   - ID (A, B, etc.)
   - Duration
   - ES (Early Start) | EF (Early Finish)
   - LS (Late Start)  | LF (Late Finish)
   - Slack (Float)

3. CALCULATIONS:
   - Start Project at Day 0.
   - Forward Pass: ES = Max(Predecessor EF). EF = ES + Duration.
   - Backward Pass: LF = Min(Successor LS). LS = LF - Duration.
   - Slack = LS - ES.

4. CRITICAL PATH:
   - Identify activities with Slack = 0.
   - Highlight these nodes and arrows in RED.

5. OUTPUT:
   - Save as: ~/Diagrams/construction_pert.drawio
   - Export as: ~/Diagrams/construction_pert.pdf
INSTEOF
chown ga:ga /home/ga/Desktop/pert_instructions.txt

# Remove any previous files to ensure clean state
rm -f /home/ga/Diagrams/construction_pert.drawio
rm -f /home/ga/Diagrams/construction_pert.pdf

# Kill any existing draw.io processes
pkill -f "drawio" 2>/dev/null || true
sleep 2

# Launch draw.io with a blank diagram
echo "Launching draw.io..."
export DISPLAY=:1
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox &"
sleep 8

# Dismiss update dialog if present (aggressive check)
echo "Checking for update dialogs..."
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "update\|confirm"; then
        DISPLAY=:1 xdotool key Escape
        sleep 0.5
    fi
done

# Maximize the window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== PERT/CPM task setup complete ==="