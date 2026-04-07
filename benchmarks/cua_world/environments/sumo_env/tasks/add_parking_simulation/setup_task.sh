#!/bin/bash
echo "=== Setting up add_parking_simulation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and have proper permissions
mkdir -p /home/ga/SUMO_Scenarios/bologna_pasubio
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Scenarios
chown -R ga:ga /home/ga/SUMO_Output

# Clean up any potential files from previous runs
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_parking.add.xml
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/parking_vehicles.rou.xml
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_parking.sumocfg
rm -f /home/ga/SUMO_Output/parking_output.xml
rm -f /home/ga/SUMO_Output/tripinfos_parking.xml
rm -f /home/ga/SUMO_Output/sumo_parking_log.txt

# Start a terminal for the agent to use
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="