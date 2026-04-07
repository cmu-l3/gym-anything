#!/bin/bash
echo "=== Setting up configure_visualization task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean any previous output
rm -rf /home/ga/SUMO_Output/* 2>/dev/null || true
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Kill any existing SUMO processes
kill_sumo
sleep 2

# Clean up scenario logs
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/sumo_log.txt 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/tripinfos.xml 2>/dev/null || true

# Modify the configuration to ensure steps are logged (for programmatic verification)
# We change <no-step-log value="true"/> to "false" so we can track the progress
sed -i 's/<no-step-log value="true"\/>/<no-step-log value="false"\/>/' /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg

# Launch sumo-gui with the Bologna Pasubio scenario (loaded but not started)
# --delay 100 ensures the simulation doesn't run too fast for the agent to observe
echo "Launching sumo-gui with Bologna Pasubio scenario..."
su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo sumo-gui -c /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg --delay 100 > /tmp/sumo_gui.log 2>&1 &"

# Wait for sumo-gui window to appear
sleep 3
wait_for_window "sumo-gui\|SUMO" 30

# Give it time to fully load
sleep 3

# Focus and maximize the window for the agent
focus_and_maximize "sumo-gui\|SUMO"
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "sumo-gui is open with Bologna Pasubio scenario."