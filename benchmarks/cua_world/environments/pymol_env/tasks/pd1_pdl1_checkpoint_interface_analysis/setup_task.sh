#!/bin/bash
echo "=== Setting up PD-1/PD-L1 Checkpoint Interface Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Pre-download 4ZQK to local cache to ensure reliability
# The agent is still expected to 'fetch 4ZQK' or 'load' it directly.
if [ ! -f "$PDB_DIR/4ZQK.pdb" ]; then
    echo "Downloading PDB:4ZQK (PD-1/PD-L1 complex)..."
    wget -q "https://files.rcsb.org/download/4ZQK.pdb" -O "$PDB_DIR/4ZQK.pdb" 2>/dev/null
    chown ga:ga "$PDB_DIR/4ZQK.pdb"
fi

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/pd1_pdl1_interface.png
rm -f /home/ga/PyMOL_Data/pd1_pdl1_interface_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/pd1_pdl1_start_ts

# Launch PyMOL with an empty workspace
launch_pymol

# Wait for UI to stabilize and take initial screenshot
sleep 2
take_screenshot /tmp/pd1_pdl1_start_screenshot.png

echo "=== Setup Complete ==="