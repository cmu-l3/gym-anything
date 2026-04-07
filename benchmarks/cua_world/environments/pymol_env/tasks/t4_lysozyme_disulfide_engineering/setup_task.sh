#!/bin/bash
echo "=== Setting up T4 Lysozyme Disulfide Engineering Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 2LZM (Wild-type T4 Lysozyme)
if [ ! -f "$PDB_DIR/2LZM.pdb" ]; then
    echo "Downloading PDB:2LZM (Wild-type T4 Lysozyme)..."
    wget -q "https://files.rcsb.org/download/2LZM.pdb" -O "$PDB_DIR/2LZM.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/2LZM.pdb" ]; then
        echo "ERROR: Failed to download 2LZM.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/2LZM.pdb"
fi
echo "PDB:2LZM available at $PDB_DIR/2LZM.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp to prevent anti-gaming
rm -f /home/ga/PyMOL_Data/images/t4l_engineered_disulfide.png
rm -f /home/ga/PyMOL_Data/t4l_disulfide_report.txt

# Record task start timestamp
date +%s > /tmp/t4l_task_start_ts

# Launch PyMOL with the required structure
launch_pymol_with_file "$PDB_DIR/2LZM.pdb"

# Wait for UI to stabilize and take the initial screenshot
sleep 2
take_screenshot /tmp/t4l_start_screenshot.png

echo "=== Setup Complete ==="