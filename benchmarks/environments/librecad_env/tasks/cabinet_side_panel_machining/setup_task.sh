#!/bin/bash
set -e
echo "=== Setting up Cabinet Side Panel task ==="

# 1. Prepare the Specification File
# We write this fresh every time to ensure the agent has the correct data
cat > /home/ga/Documents/cabinet_spec.txt << 'EOF'
Project: Kitchen_Job_2024
Unit: B101 (Base Cabinet)
Part: Side_Panel_Left_01

Dimensions (mm):
Height: 720
Depth: 560
Toe_Kick_Height: 100
Toe_Kick_Depth: 70
Toe_Kick_Location: Front_Bottom (Bottom-Right in drawing, assuming back is Left)
# Note for Agent: Usually in cabinet making, Back is X=0 or X=Max. 
# Let's assume Back is at X=0 (Left) for this drawing.
# Therefore:
# - Back edge of panel is at X=0
# - Front edge of panel is at X=560
# - Toe Kick is at Bottom-Right corner (X=560, Y=0)

Back_Groove (mm):
Width: 6
Distance_From_Back_Edge: 20
Note: Groove runs full height (Y=0 to Y=720).

Drilling_System32 (mm):
Hole_Diameter: 5
Front_Back_Inset: 37
# Holes are 37mm from Front Edge and 37mm from Back Edge
Vertical_Spacing: 32
First_Hole_Y_Position: 192
Last_Hole_Max_Y: 650
EOF

chown ga:ga /home/ga/Documents/cabinet_spec.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/LibreCAD/side_panel_cnc.dxf
mkdir -p /home/ga/Documents/LibreCAD
chown -R ga:ga /home/ga/Documents/LibreCAD

# 3. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start LibreCAD
# Kill any existing instances first
pkill -f librecad 2>/dev/null || true
sleep 2

echo "Starting LibreCAD..."
su - ga -c "DISPLAY=:1 librecad > /tmp/librecad.log 2>&1 &"

# 5. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "LibreCAD"; then
        echo "LibreCAD window found."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "LibreCAD" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
# Focus window
DISPLAY=:1 wmctrl -a "LibreCAD" 2>/dev/null || true

# 6. Open the text editor with the spec file so the agent sees it immediately?
# The instructions say "Open and read...". It's better if the agent has to open it,
# but we can leave it on the desktop or open a terminal.
# Let's just ensure the file is there. We won't auto-open a text editor to avoid clutter,
# as the agent needs to focus on LibreCAD.

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="