#!/bin/bash
echo "=== Setting up BRAF DFG-Flip Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 3OG7 (active / DFG-in state)
if [ ! -f "$PDB_DIR/3OG7.pdb" ]; then
    echo "Downloading PDB:3OG7..."
    wget -q "https://files.rcsb.org/download/3OG7.pdb" -O "$PDB_DIR/3OG7.pdb" 2>/dev/null
    if [ -f "$PDB_DIR/3OG7.pdb" ]; then
        chown ga:ga "$PDB_DIR/3OG7.pdb"
    fi
fi

# Download 1UWH (inactive / DFG-out state)
if [ ! -f "$PDB_DIR/1UWH.pdb" ]; then
    echo "Downloading PDB:1UWH..."
    wget -q "https://files.rcsb.org/download/1UWH.pdb" -O "$PDB_DIR/1UWH.pdb" 2>/dev/null
    if [ -f "$PDB_DIR/1UWH.pdb" ]; then
        chown ga:ga "$PDB_DIR/1UWH.pdb"
    fi
fi

echo "PDB files cached locally at $PDB_DIR"

# Ensure output directories exist with correct permissions
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete any stale outputs BEFORE recording the start timestamp
rm -f /home/ga/PyMOL_Data/images/braf_dfg_flip.png
rm -f /home/ga/PyMOL_Data/braf_inhibition_report.txt

# Record task start timestamp (integer seconds) for anti-gaming verification
date +%s > /tmp/braf_dfg_start_ts

# Launch PyMOL empty so the agent must fetch/load structures themselves
launch_pymol

# Give the UI time to render, then take an initial screenshot
sleep 2
take_screenshot /tmp/braf_dfg_start_screenshot.png

echo "=== Setup Complete ==="