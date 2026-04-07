#!/bin/bash
echo "=== Setting up p53 DNA Hotspot Analysis task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/p53_dna_hotspots.png 2>/dev/null || true
rm -f /home/ga/PyMOL_Data/p53_hotspot_report.txt 2>/dev/null || true

# Record task start timestamp (integer seconds)
date +%s > /tmp/p53_task_start_ts

# Kill any existing PyMOL instance
kill_pymol

# Launch PyMOL fresh (without pre-loading a structure, forcing the agent to fetch it)
echo "Launching PyMOL..."
launch_pymol

# Wait for PyMOL to stabilize and take an initial screenshot
sleep 3
take_screenshot /tmp/p53_task_start_screenshot.png

echo "=== Task setup complete ==="