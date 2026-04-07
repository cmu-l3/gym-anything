#!/bin/bash
echo "=== Setting up galaxy_3d_surface_plot task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming file modification checks)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/AstroImages/processed
rm -f /home/ga/AstroImages/processed/galaxy_core_surface.png
chown -R ga:ga /home/ga/AstroImages

# Launch AstroImageJ and wait for it to be ready
launch_astroimagej 60

# Wait for UI to fully render
sleep 3

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="