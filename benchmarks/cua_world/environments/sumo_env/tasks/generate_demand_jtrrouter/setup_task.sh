#!/bin/bash
echo "=== Setting up generate_demand_jtrrouter task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
OUTPUT_DIR="/home/ga/SUMO_Output"
sudo -u ga mkdir -p "$OUTPUT_DIR"
sudo -u ga rm -f "$OUTPUT_DIR/flows.xml" "$OUTPUT_DIR/turns.xml" "$OUTPUT_DIR/jtr_routes.rou.xml" "$OUTPUT_DIR/jtr.sumocfg" "$OUTPUT_DIR/jtr_tripinfo.xml"

# Open a terminal for the user to work in
echo "Opening terminal for agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Output &"
sleep 3

# Maximize the terminal
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="