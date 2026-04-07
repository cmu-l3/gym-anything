#!/bin/bash
echo "=== Setting up Ubiquitin Lysine SASA Mapping Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1UBQ (Ubiquitin) if not already present
if [ ! -f "$PDB_DIR/1UBQ.pdb" ]; then
    echo "Downloading PDB:1UBQ..."
    wget -q "https://files.rcsb.org/download/1UBQ.pdb" -O "$PDB_DIR/1UBQ.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1UBQ.pdb" ]; then
        echo "ERROR: Failed to download 1UBQ.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1UBQ.pdb"
fi
echo "PDB:1UBQ available at $PDB_DIR/1UBQ.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ubq_lysines.png
rm -f /home/ga/PyMOL_Data/ubiquitin_lysine_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ubq_lysine_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1UBQ.pdb"

sleep 2
take_screenshot /tmp/ubq_lysine_start_screenshot.png

echo "=== Setup Complete ==="