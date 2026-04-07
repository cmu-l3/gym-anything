#!/bin/bash
set -e
echo "=== Setting up modify_plot_with_weather_data task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing applications
kill_all_apps

# Ensure data files are in place
cp /workspace/data/pittsburgh_weather.csv /home/ga/Documents/pittsburgh_weather.csv

chown -R ga:ga /home/ga/Documents

# Open plot.tcl in gedit for the agent to edit
launch_gedit "/home/ga/Documents/plot.tcl"

# Open a terminal for running commands (cd to Documents)
launch_terminal "/home/ga/Documents"

# Arrange windows: gedit on the left, terminal on the right
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "plot.tcl" -e 0,0,0,960,1080 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "gedit" -e 0,0,0,960,1080 2>/dev/null || true
sleep 1

# Position terminal on the right half
TERM_WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i "xterm\|ga@" | head -1 | awk '{print $1}')
if [ -n "$TERM_WID" ]; then
    DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$TERM_WID" -e 0,960,0,960,1080 2>/dev/null || true
fi

sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== modify_plot_with_weather_data task setup complete ==="
echo "gedit is open with plot.tcl, terminal is open for running scripts."
echo "Weather data CSV is at ~/Documents/pittsburgh_weather.csv"
