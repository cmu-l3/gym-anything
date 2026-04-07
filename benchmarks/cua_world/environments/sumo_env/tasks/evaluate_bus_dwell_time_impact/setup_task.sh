#!/bin/bash
echo "=== Setting up evaluate_bus_dwell_time_impact task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and have proper permissions
mkdir -p /home/ga/SUMO_Scenarios/bologna_pasubio
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Scenarios
chown -R ga:ga /home/ga/SUMO_Output

# Clean up any potential files from previous runs to ensure a clean state
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/pasubio_busses_slow.rou.xml
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_slow_buses.sumocfg
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/tripinfos_slow.xml
rm -f /home/ga/SUMO_Output/tripinfos_slow.xml
rm -f /home/ga/SUMO_Output/bus_impact_report.txt

# Ensure a terminal is open and focused for the user to work
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait a moment to ensure UI settles
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="