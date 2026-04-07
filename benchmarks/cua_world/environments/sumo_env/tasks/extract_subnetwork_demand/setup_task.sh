#!/bin/bash
echo "=== Setting up extract_subnetwork_demand task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean of previous artifacts
mkdir -p /home/ga/SUMO_Output
rm -f /home/ga/SUMO_Output/micro.net.xml
rm -f /home/ga/SUMO_Output/micro.rou.xml
rm -f /home/ga/SUMO_Output/micro.sumocfg
chown -R ga:ga /home/ga/SUMO_Output

# Ensure the original scenario exists
SCENARIO_DIR="/home/ga/SUMO_Scenarios/bologna_acosta"
if [ ! -d "$SCENARIO_DIR" ]; then
    echo "ERROR: Original scenario directory not found!"
    exit 1
fi

# Launch a terminal for the agent since this is a heavily CLI-driven task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"
    sleep 3
fi

# Focus and maximize the terminal
focus_and_maximize "Terminal"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="