#!/bin/bash
echo "=== Setting up Ras p21 Nucleotide Binding Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 5P21 (H-Ras p21 with GppNHp/GNP)
if [ ! -f "$PDB_DIR/5P21.pdb" ]; then
    echo "Downloading PDB:5P21 (H-Ras p21 with GppNHp)..."
    wget -q "https://files.rcsb.org/download/5P21.pdb" -O "$PDB_DIR/5P21.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/5P21.pdb" ]; then
        echo "ERROR: Failed to download 5P21.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/5P21.pdb"
fi
echo "PDB:5P21 available at $PDB_DIR/5P21.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/ras_nucleotide.png
rm -f /home/ga/PyMOL_Data/ras_nucleotide_report.txt

# Record task start timestamp (integer seconds — Lesson 15)
date +%s > /tmp/ras_nucleotide_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/5P21.pdb"

sleep 2
take_screenshot /tmp/ras_nucleotide_start_screenshot.png

echo "=== Setup Complete ==="
