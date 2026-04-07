#!/bin/bash
echo "=== Setting up Estrogen Receptor Antagonism Mechanism Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1ERE (Agonist-bound ER alpha)
if [ ! -f "$PDB_DIR/1ERE.pdb" ]; then
    echo "Downloading PDB:1ERE..."
    wget -q "https://files.rcsb.org/download/1ERE.pdb" -O "$PDB_DIR/1ERE.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1ERE.pdb" ]; then
        echo "ERROR: Failed to download 1ERE.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1ERE.pdb"
fi

# Download 1ERR (Antagonist-bound ER alpha)
if [ ! -f "$PDB_DIR/1ERR.pdb" ]; then
    echo "Downloading PDB:1ERR..."
    wget -q "https://files.rcsb.org/download/1ERR.pdb" -O "$PDB_DIR/1ERR.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1ERR.pdb" ]; then
        echo "ERROR: Failed to download 1ERR.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1ERR.pdb"
fi
echo "PDBs 1ERE and 1ERR available at $PDB_DIR"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/er_helix12_shift.png
rm -f /home/ga/PyMOL_Data/er_antagonism_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/er_antagonism_start_ts

# Launch PyMOL with an empty session (agent must fetch/load structures themselves)
launch_pymol

# Take initial screenshot
sleep 2
take_screenshot /tmp/er_antagonism_start_screenshot.png

echo "=== Setup Complete ==="