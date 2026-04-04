#!/bin/bash
echo "=== Setting up complete_maze task ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

# Navigate to the Dino/Sports category which contains the Maze activity.
# The green dinosaur icon is at VG (575,65) in 1280x720 → actual (862, 97) in 1920x1080.
# This category contains: Football game, Maze, Memory game with images, Programming maze, etc.
DISPLAY=:1 xdotool mousemove 862 97 click 1
sleep 3

echo "=== complete_maze task setup complete ==="
echo "GCompris is now showing the Dino/Sports/Misc category."
echo "The Maze activity icon (penguin in brick maze) is visible."
echo "Agent must: click the Maze tile → use arrow keys to navigate penguin to the door."
