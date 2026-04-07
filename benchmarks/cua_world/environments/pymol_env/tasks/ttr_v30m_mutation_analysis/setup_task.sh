#!/bin/bash
echo "=== Setting up Transthyretin V30M Mutation Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1TTA (Wild-Type Transthyretin)
if [ ! -f "$PDB_DIR/1TTA.pdb" ]; then
    echo "Downloading PDB:1TTA..."
    wget -q "https://files.rcsb.org/download/1TTA.pdb" -O "$PDB_DIR/1TTA.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1TTA.pdb" ]; then
        echo "ERROR: Failed to download 1TTA.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1TTA.pdb"
fi

# Download 1TTC (V30M Mutant Transthyretin)
if [ ! -f "$PDB_DIR/1TTC.pdb" ]; then
    echo "Downloading PDB:1TTC..."
    wget -q "https://files.rcsb.org/download/1TTC.pdb" -O "$PDB_DIR/1TTC.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1TTC.pdb" ]; then
        echo "ERROR: Failed to download 1TTC.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1TTC.pdb"
fi

echo "Structures 1TTA and 1TTC are available at $PDB_DIR"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale output files BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ttr_v30m_clash.png
rm -f /home/ga/PyMOL_Data/ttr_v30m_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ttr_v30m_start_ts

# Launch PyMOL empty (agent must load and superimpose both structures)
launch_pymol

# Take initial screenshot
sleep 2
take_screenshot /tmp/ttr_v30m_start_screenshot.png

echo "=== Setup Complete ==="