#!/bin/bash
echo "=== Setting up Myoglobin SASA Core Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1A6M (Sperm Whale Myoglobin)
if [ ! -f "$PDB_DIR/1A6M.pdb" ]; then
    echo "Downloading PDB:1A6M (Sperm Whale Myoglobin)..."
    wget -q "https://files.rcsb.org/download/1A6M.pdb" -O "$PDB_DIR/1A6M.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1A6M.pdb" ]; then
        echo "ERROR: Failed to download 1A6M.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1A6M.pdb"
fi
echo "PDB:1A6M available at $PDB_DIR/1A6M.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/myoglobin_sasa.png
rm -f /home/ga/PyMOL_Data/myoglobin_sasa_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/myoglobin_sasa_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1A6M.pdb"

# Take initial screenshot
sleep 2
take_screenshot /tmp/myoglobin_sasa_start_screenshot.png

echo "=== Setup Complete ==="