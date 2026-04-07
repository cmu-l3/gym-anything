#!/bin/bash
echo "=== Setting up Nucleosome Histone-DNA Contact Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1AOI (Nucleosome core particle)
if [ ! -f "$PDB_DIR/1AOI.pdb" ]; then
    echo "Downloading PDB:1AOI (Nucleosome core particle)..."
    wget -q "https://files.rcsb.org/download/1AOI.pdb" -O "$PDB_DIR/1AOI.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1AOI.pdb" ]; then
        echo "ERROR: Failed to download 1AOI.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1AOI.pdb"
fi
echo "PDB:1AOI available at $PDB_DIR/1AOI.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/nucleosome_contacts.png
rm -f /home/ga/PyMOL_Data/nucleosome_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/nucleosome_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1AOI.pdb"

sleep 2
take_screenshot /tmp/nucleosome_start_screenshot.png

echo "=== Setup Complete ==="