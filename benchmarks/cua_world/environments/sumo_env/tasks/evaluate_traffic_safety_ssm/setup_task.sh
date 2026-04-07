#!/bin/bash
echo "=== Setting up evaluate_traffic_safety_ssm task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Kill any existing SUMO processes
kill_sumo
sleep 1

# Ensure fresh state: delete output files that the agent is supposed to create
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/run_ssm.sumocfg 2>/dev/null || true
rm -f /home/ga/SUMO_Output/ssm.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Output/conflict_count.txt 2>/dev/null || true
rm -f /home/ga/SUMO_Output/tripinfos.xml 2>/dev/null || true
rm -f /home/ga/SUMO_Scenarios/bologna_pasubio/sumo_log.txt 2>/dev/null || true

# Open a terminal for the agent in the correct directory
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_pasubio &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="