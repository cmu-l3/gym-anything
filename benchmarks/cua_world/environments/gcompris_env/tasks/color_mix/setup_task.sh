#!/bin/bash
echo "=== Setting up color_mix task ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

# Navigate to the Science/Experiment category.
# The Pig icon is at VG (455,65) in 1280x720 → actual (682, 97) in 1920x1080.
# This opens Experiment/History/Geography tabs; Experiment tab shows by default.
# Activities visible: Operate a canal lock, Explore farm animals, Binary bulbs,
# Gravity, Watercycle, Mixing paint colors, Mixing light colors.
DISPLAY=:1 xdotool mousemove 682 97 click 1
sleep 3

echo "=== color_mix task setup complete ==="
echo "GCompris is now showing the Science/Experiment category."
echo "Visible activities include: Mixing paint colors (paint palette icon), Mixing light colors."
echo "Agent must: click 'Mixing paint colors' tile → use +/- buttons on paint tubes to match the target color → click OK."
