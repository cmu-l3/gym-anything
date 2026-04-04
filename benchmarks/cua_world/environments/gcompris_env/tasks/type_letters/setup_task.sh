#!/bin/bash
echo "=== Setting up type_letters task ==="

# Load utilities
source /workspace/scripts/task_utils.sh

# Kill any existing GCompris instances
kill_gcompris

# Launch GCompris at the main menu
launch_gcompris
sleep 3
maximize_gcompris
sleep 2

# Navigate to the ABC/Reading category.
# The Cow-with-ABC icon is at VG (965,65) in 1280x720 → actual (1447, 97) in 1920x1080.
# This opens the Letters/Words/Vocabulary category.
# The Letters tab is shown by default.
DISPLAY=:1 xdotool mousemove 1447 97 click 1
sleep 3

echo "=== type_letters task setup complete ==="
echo "GCompris is now showing the ABC/Reading/Letters category."
echo "Visible activities include: Baby keyboard, A baby word processor, Draw letters,"
echo "Alphabet sequence, Click on a lowercase letter, Click on an uppercase letter, Simple letters."
echo "Agent must: click 'Alphabet sequence' tile → press letters a,b,c,d,e... in order as they appear."
