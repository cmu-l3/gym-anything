#!/bin/bash
set -e
echo "=== Setting up create_element_browser task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing applications
kill_all_apps

# Ensure data files are in place
cp /workspace/data/periodic_table.csv /home/ga/Documents/periodic_table.csv

# Create an empty starter file for the agent
cat > /home/ga/Documents/element_browser.tcl << 'EOF'
#!/usr/bin/wish
# Periodic Table Element Browser
# Data source: IUPAC 2021 Standard Atomic Weights
# Data file: ~/Documents/periodic_table.csv
#
# TODO: Read the CSV file, create a GUI with:
#   1. A search entry field at the top
#   2. A scrollable listbox showing element names
#   3. A detail panel showing selected element properties

package require Tk

EOF

chown -R ga:ga /home/ga/Documents

# Open the starter file in gedit
launch_gedit "/home/ga/Documents/element_browser.tcl"

# Open a terminal for running commands
launch_terminal "/home/ga/Documents"

# Arrange windows side by side
sleep 2
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r "element_browser" -e 0,0,0,960,1080 2>/dev/null || \
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

echo "=== create_element_browser task setup complete ==="
echo "gedit is open with element_browser.tcl skeleton, terminal is available."
echo "Periodic table data is at ~/Documents/periodic_table.csv"
