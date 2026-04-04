#!/bin/bash
echo "=== Setting up run_simulation task ==="

source /workspace/scripts/task_utils.sh

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Clean up any previous output files
rm -f /home/ga/SUMO_Scenarios/bologna_acosta/tripinfos.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_acosta/sumo_log.txt 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_acosta/e1_output.xml 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/SUMO_Output
chown ga:ga /home/ga/SUMO_Output

# Launch sumo-gui with the Bologna Acosta scenario (loaded but not started)
echo "Launching sumo-gui with Bologna Acosta scenario..."
su - ga -c "DISPLAY=:1 SUMO_HOME=/usr/share/sumo sumo-gui -c /home/ga/SUMO_Scenarios/bologna_acosta/run.sumocfg --delay 200 > /tmp/sumo_gui.log 2>&1 &"

# Wait for sumo-gui window to appear
sleep 3
wait_for_window "sumo-gui\|SUMO" 30

# Give it time to fully load
sleep 3

# Focus and maximize
focus_and_maximize "sumo-gui\|SUMO"
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Open visualization settings (F9), change vehicle coloring to 'by speed', save screenshot."
