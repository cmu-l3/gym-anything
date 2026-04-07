#!/bin/bash
echo "=== Setting up subsea_hydrodynamic_simulation task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/CoppeliaSim/exports
chown -R ga:ga /home/ga/Documents/CoppeliaSim

# Remove pre-existing output files
rm -f /home/ga/Documents/CoppeliaSim/exports/hydrodynamics.csv 2>/dev/null || true
rm -f /home/ga/Documents/CoppeliaSim/exports/hydrodynamics_report.json 2>/dev/null || true

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_ts

# Launch CoppeliaSim with an empty scene
launch_coppeliasim

focus_coppeliasim
maximize_coppeliasim

sleep 2
dismiss_dialogs

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "CoppeliaSim is running with an empty scene. Agent must use the ZMQ API to inject custom physics forces."