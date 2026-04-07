#!/bin/bash
echo "=== Setting up Hemoglobin T/R Allostery Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# 4HHB should already be present from install_pymol.sh
if [ ! -f "$PDB_DIR/4HHB.pdb" ]; then
    echo "Downloading PDB:4HHB (T-state deoxy hemoglobin)..."
    wget -q "https://files.rcsb.org/download/4HHB.pdb" -O "$PDB_DIR/4HHB.pdb" 2>/dev/null
    chown ga:ga "$PDB_DIR/4HHB.pdb"
fi

# Download 1HHO (R-state oxy hemoglobin)
if [ ! -f "$PDB_DIR/1HHO.pdb" ]; then
    echo "Downloading PDB:1HHO (R-state oxy hemoglobin)..."
    wget -q "https://files.rcsb.org/download/1HHO.pdb" -O "$PDB_DIR/1HHO.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1HHO.pdb" ]; then
        echo "ERROR: Failed to download 1HHO.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1HHO.pdb"
fi
echo "PDB:4HHB and PDB:1HHO available"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/hemo_superposition.png
rm -f /home/ga/PyMOL_Data/hemo_rmsd_report.txt

# Record task start timestamp (integer seconds — Lesson 15)
date +%s > /tmp/hemo_allostery_start_ts

# Launch PyMOL with 4HHB (agent must also load 1HHO)
launch_pymol_with_file "$PDB_DIR/4HHB.pdb"

sleep 2
take_screenshot /tmp/hemo_allostery_start_screenshot.png

echo "=== Setup Complete ==="
