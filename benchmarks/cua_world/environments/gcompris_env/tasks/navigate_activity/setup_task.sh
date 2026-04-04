#!/bin/bash
echo "=== Setting up navigate_activity task ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

# Navigate into the Math/Numbers category (sheep icon at actual 1057, 97).
# This puts the agent into a non-empty category view showing Math activities
# with Numeration, Arithmetic, and Measures tabs visible.
# The agent must still discover the Arithmetic tab and find Learn additions.
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1057 97 click 1
sleep 3

echo "=== navigate_activity task setup complete ==="
echo "GCompris is now showing the Math/Numbers category (Numeration tab default)."
echo "Visible tabs: Numeration, Arithmetic, Measures."
echo "Agent must: click the Arithmetic tab → find and open 'Learn additions'."
