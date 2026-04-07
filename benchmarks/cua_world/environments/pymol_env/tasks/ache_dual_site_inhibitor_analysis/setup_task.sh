#!/bin/bash
echo "=== Setting up AChE Dual-Site Inhibitor Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 4EY7 (AChE with donepezil)
if [ ! -f "$PDB_DIR/4EY7.pdb" ]; then
    echo "Downloading PDB:4EY7 (Human AChE with donepezil)..."
    wget -q "https://files.rcsb.org/download/4EY7.pdb" -O "$PDB_DIR/4EY7.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/4EY7.pdb" ]; then
        echo "ERROR: Failed to download 4EY7.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/4EY7.pdb"
fi
echo "PDB:4EY7 available at $PDB_DIR/4EY7.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ache_gorge.png
rm -f /home/ga/PyMOL_Data/ache_binding_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ache_task_start_ts

# Launch PyMOL with the structure pre-loaded to save time
launch_pymol_with_file "$PDB_DIR/4EY7.pdb"

# Allow UI to stabilize and take initial screenshot
sleep 2
take_screenshot /tmp/ache_task_start_screenshot.png

echo "=== Setup Complete ==="