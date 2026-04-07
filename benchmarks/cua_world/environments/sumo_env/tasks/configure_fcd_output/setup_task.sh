#!/bin/bash
echo "=== Setting up FCD output configuration task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
rm -f /home/ga/SUMO_Output/pasubio_fcd.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Output/tripinfos.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_fcd.sumocfg 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Ensure the Bologna Pasubio scenario is intact
if [ ! -f /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg ]; then
    echo "ERROR: Bologna Pasubio scenario not found!"
    exit 1
fi

# Record initial state of output directory
ls -la /home/ga/SUMO_Output/ > /tmp/initial_output_state.txt 2>/dev/null || echo "empty" > /tmp/initial_output_state.txt

# Kill any existing SUMO processes
kill_sumo
sleep 2

# Launch sumo-gui with the Pasubio scenario
echo "Launching sumo-gui with Bologna Pasubio scenario..."
su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo sumo-gui -c /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg &"
sleep 5

# Wait for sumo-gui window
if wait_for_window "sumo" 30; then
    echo "sumo-gui started successfully"
else
    echo "Warning: sumo-gui window not detected, retrying..."
    su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo sumo-gui -c /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg &"
    sleep 5
    wait_for_window "sumo" 20 || echo "Warning: sumo-gui may not have started"
fi

# Maximize and focus the window
sleep 2
focus_and_maximize "sumo" || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="