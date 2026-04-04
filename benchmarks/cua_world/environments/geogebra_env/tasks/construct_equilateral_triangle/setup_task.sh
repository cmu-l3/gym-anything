#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Construct Equilateral Triangle Task ==="

# Kill any existing GeoGebra processes
kill_geogebra ga
sleep 1

# Ensure project directory exists
mkdir -p /home/ga/Documents/GeoGebra/projects
chown -R ga:ga /home/ga/Documents/GeoGebra

# Remove any existing file with the expected name (for clean test)
rm -f /home/ga/Documents/GeoGebra/projects/equilateral_triangle.ggb 2>/dev/null || true

# Record initial state for verification
echo "0" > /tmp/initial_ggb_count
find /home/ga/Documents/GeoGebra -name "*.ggb" 2>/dev/null | wc -l > /tmp/initial_ggb_count

# Record task start time for timestamp validation (prevents pre-made file attacks)
date +%s > /tmp/task_start_time
echo "Task started at: $(cat /tmp/task_start_time)"

# Launch GeoGebra
echo "Launching GeoGebra..."
launch_geogebra ga

if ! wait_for_process "geogebra" 30; then
    echo "ERROR: GeoGebra failed to start"
    exit 1
fi

if ! wait_for_window "GeoGebra" 30; then
    echo "ERROR: GeoGebra window did not appear"
    exit 1
fi

# Click on center of the screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus and maximize GeoGebra window
focus_geogebra
sleep 0.5
maximize_geogebra
sleep 1

# Randomize viewport to prevent pre-computed coordinate attacks
# This makes the agent need to actually look at the screen to find positions
if [ "${RANDOMIZE_VIEWPORT:-1}" != "0" ]; then
    echo "Randomizing viewport to prevent coordinate memorization..."
    randomize_geogebra_viewport ga :1
    sleep 0.5
fi

echo "=== Construct Equilateral Triangle Task Setup Complete ==="
echo "Instructions:"
echo "  1. Use GeoGebra tools to construct an equilateral triangle"
echo "  2. Create points A, B, C where all sides are equal"
echo "  3. You can use:"
echo "     - Point tool to create points"
echo "     - Circle tool (with center and radius) to find equidistant points"
echo "     - Segment or Polygon tool to connect the vertices"
echo "  4. Save the file as: ~/Documents/GeoGebra/projects/equilateral_triangle.ggb"
echo "  5. Use File -> Save or Ctrl+S"
