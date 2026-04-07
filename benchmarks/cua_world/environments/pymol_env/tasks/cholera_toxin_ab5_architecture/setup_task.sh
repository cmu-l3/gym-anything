#!/bin/bash
echo "=== Setting up Cholera Toxin AB5 Architecture Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1XTC (Cholera Toxin)
if [ ! -f "$PDB_DIR/1XTC.pdb" ]; then
    echo "Downloading PDB:1XTC (Cholera Toxin)..."
    wget -q "https://files.rcsb.org/download/1XTC.pdb" -O "$PDB_DIR/1XTC.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1XTC.pdb" ]; then
        echo "ERROR: Failed to download 1XTC.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1XTC.pdb"
fi
echo "PDB:1XTC available at $PDB_DIR/1XTC.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/cholera_ab5.png
rm -f /home/ga/PyMOL_Data/cholera_interface_report.txt

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/cholera_ab5_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1XTC.pdb"

# Wait for rendering and take initial screenshot
sleep 2
take_screenshot /tmp/cholera_ab5_start_screenshot.png

echo "=== Setup Complete ==="