#!/bin/bash
echo "=== Setting up tRNA Domain Architecture Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1EHZ (Yeast tRNA-Phe)
if [ ! -f "$PDB_DIR/1EHZ.pdb" ]; then
    echo "Downloading PDB:1EHZ (Yeast tRNA-Phe)..."
    wget -q "https://files.rcsb.org/download/1EHZ.pdb" -O "$PDB_DIR/1EHZ.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1EHZ.pdb" ]; then
        echo "ERROR: Failed to download 1EHZ.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1EHZ.pdb"
fi
echo "PDB:1EHZ available at $PDB_DIR/1EHZ.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/trna_domains.png
rm -f /home/ga/PyMOL_Data/trna_structure_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/trna_task_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1EHZ.pdb"

# Give UI time to stabilize, then take initial screenshot
sleep 3
take_screenshot /tmp/trna_task_start_screenshot.png

echo "=== Setup Complete ==="