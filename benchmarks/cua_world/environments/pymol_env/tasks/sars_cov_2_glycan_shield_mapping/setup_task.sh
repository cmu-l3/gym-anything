#!/bin/bash
echo "=== Setting up SARS-CoV-2 Glycan Shield Mapping Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/glycan_shield.png
rm -f /home/ga/PyMOL_Data/glycan_report.txt
rm -f /tmp/sars_cov_2_result.json

# Record task start timestamp (integer seconds)
date +%s > /tmp/sars_cov_2_start_ts

# Launch PyMOL empty (the agent must fetch 6VXX over the network)
launch_pymol

# Wait for UI and take initial screenshot
sleep 3
take_screenshot /tmp/sars_cov_2_start_screenshot.png

echo "=== Setup Complete ==="