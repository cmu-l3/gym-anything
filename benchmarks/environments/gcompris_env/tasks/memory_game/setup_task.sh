#!/bin/bash
echo "=== Setting up memory_game task ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

# Navigate to the Dino/Sports/Misc category which contains memory game activities.
# The green dinosaur icon is at VG (575,65) in 1280x720 → actual (862, 97) in 1920x1080.
# Activities visible: Football game, Maze, Memory game with images against Tux,
# Memory game with images, Programming maze, A simple drawing activity, Hexagon.
DISPLAY=:1 xdotool mousemove 862 97 click 1
sleep 3

echo "=== memory_game task setup complete ==="
echo "GCompris is now showing the Dino/Sports/Misc category."
echo "Visible activities include: Memory game with images (4-card grid icon)."
echo "Agent must: click 'Memory game with images' tile → click cards to find matching pairs."
