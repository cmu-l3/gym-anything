#!/bin/bash
echo "=== Setting up evaluate_av_idm_impact task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist and permissions are correct
mkdir -p /home/ga/SUMO_Output
chown -R ga:ga /home/ga/SUMO_Output

# Clean any artifacts from previous runs
rm -f /home/ga/SUMO_Output/tripinfos_*.xml 2>/dev/null
rm -f /home/ga/SUMO_Output/av_comparison.txt 2>/dev/null
rm -f /home/ga/SUMO_Scenarios/bologna_acosta/run_av.sumocfg 2>/dev/null
rm -f /home/ga/SUMO_Scenarios/bologna_acosta/*_av.xml 2>/dev/null

# Open a terminal for the agent since this is a CLI-heavy task
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/SUMO_Scenarios/bologna_acosta &"
    sleep 3
fi

# Maximize and focus the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial state screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="