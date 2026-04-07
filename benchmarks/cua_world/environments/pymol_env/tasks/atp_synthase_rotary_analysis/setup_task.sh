#!/bin/bash
echo "=== Setting up ATP Synthase F1 Domain Rotary Mechanism Analysis ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Pre-download 1BMF as a fallback in case the agent struggles with `fetch` and network 
# (the agent is still expected to load it)
if [ ! -f "/home/ga/PyMOL_Data/structures/1BMF.pdb" ]; then
    wget -q "https://files.rcsb.org/download/1BMF.pdb" -O "/home/ga/PyMOL_Data/structures/1BMF.pdb" 2>/dev/null || true
    chown ga:ga "/home/ga/PyMOL_Data/structures/1BMF.pdb"
fi

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/atp_synthase_f1.png
rm -f /home/ga/PyMOL_Data/f1_rotary_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/f1_rotary_start_ts

# Launch PyMOL with an empty session as instructed
launch_pymol

# Give PyMOL a moment to stabilize UI
sleep 3
take_screenshot /tmp/f1_rotary_start_screenshot.png

echo "=== Setup Complete ==="