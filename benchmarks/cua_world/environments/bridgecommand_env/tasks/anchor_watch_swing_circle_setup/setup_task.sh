#!/bin/bash
echo "=== Setting up Anchor Watch Swing Circle Task ==="

# Define paths
DOCS_DIR="/home/ga/Documents/AnchorData"
SCENARIO_DIR="/opt/bridgecommand/Scenarios/a) Anchor Watch Drill"
BC_BIN="/opt/bridgecommand/bridgecommand"

# Clean up previous run artifacts
rm -rf "$DOCS_DIR"
rm -rf "$SCENARIO_DIR"
mkdir -p "$DOCS_DIR"
chown ga:ga "$DOCS_DIR"

# Create vessel status file with task parameters
cat > "$DOCS_DIR/vessel_status.txt" << EOF
VESSEL STATUS REPORT - MV OOCL United Kingdom
=============================================
Date: 2024-05-15 08:00 UTC
Location: Solent Anchorage

Vessel Particulars:
- Name: MV OOCL United Kingdom
- Length Overall (LOA): 399.9 meters
- Beam: 58.8 meters

Anchor Status:
- Anchor Position: 50.7650 N, 001.0800 W
- Water Depth: 22 meters
- Cable on Deck: 9 Shackles (1 Shackle = 27.5 meters)
- Holding Ground: Good (Mud/Sand)

Instructions:
Calculate maximum Swing Circle radius.
Setup simulation with visual markers at this radius for cadet training.
EOF

chown ga:ga "$DOCS_DIR/vessel_status.txt"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Bridge Command is closed to start fresh
pkill -f "bridgecommand" 2>/dev/null || true
sleep 1

# Launch Bridge Command just to ensure it's ready/visible (agent needs to know it exists)
# We launch it briefly then keep it running or close it. 
# Since this is primarily a file creation task, we ensure the window is available 
# so the agent *could* test it, but we don't force them to keep it open.
# However, for the initial screenshot, let's open the Documents folder to show the input data.

echo "Opening instructions..."
su - ga -c "DISPLAY=:1 xdg-open '$DOCS_DIR/vessel_status.txt' &"
sleep 2

# Maximize the text editor
WID=$(DISPLAY=:1 wmctrl -l | grep -i "vessel_status" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="