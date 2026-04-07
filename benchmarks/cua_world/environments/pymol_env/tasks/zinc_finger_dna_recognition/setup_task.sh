#!/bin/bash
echo "=== Setting up Zinc Finger DNA Recognition Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Pre-download the structure to the local cache so 'fetch' or 'load' works reliably
if [ ! -f "/home/ga/PyMOL_Data/structures/1AAY.pdb" ]; then
    echo "Caching PDB:1AAY..."
    wget -q "https://files.rcsb.org/download/1AAY.pdb" -O "/home/ga/PyMOL_Data/structures/1AAY.pdb" 2>/dev/null || true
    chown ga:ga "/home/ga/PyMOL_Data/structures/1AAY.pdb"
fi

# Clean up any stale outputs BEFORE recording start time (Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/zif268_finger2.png
rm -f /home/ga/PyMOL_Data/zif268_report.txt

# Record task start timestamp
date +%s > /tmp/zif268_start_ts

# Launch empty PyMOL (Agent is instructed to fetch/load the structure itself)
launch_pymol

# Wait for UI to stabilize and take initial screenshot
sleep 3
take_screenshot /tmp/zif268_start_screenshot.png

echo "=== Setup Complete ==="