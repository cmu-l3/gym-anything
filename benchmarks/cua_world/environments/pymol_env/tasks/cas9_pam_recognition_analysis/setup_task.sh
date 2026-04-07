#!/bin/bash
echo "=== Setting up Cas9 PAM Recognition Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Pre-download 4UN3 to ensure it's available even if RCSB fetch fails
if [ ! -f "$PDB_DIR/4UN3.pdb" ]; then
    echo "Downloading PDB:4UN3 (Cas9-sgRNA-DNA complex)..."
    wget -q "https://files.rcsb.org/download/4UN3.pdb" -O "$PDB_DIR/4UN3.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/4UN3.pdb" ]; then
        echo "WARNING: Failed to download 4UN3.pdb, agent will need to fetch it."
        rm -f "$PDB_DIR/4UN3.pdb"
    else
        chown ga:ga "$PDB_DIR/4UN3.pdb"
    fi
fi

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/cas9_pam_recognition.png
rm -f /home/ga/PyMOL_Data/cas9_pam_report.txt

# Record task start timestamp for anti-gaming measures
date +%s > /tmp/cas9_pam_start_ts

# Launch PyMOL empty (agent must load/fetch the structure themselves)
launch_pymol

sleep 2
take_screenshot /tmp/cas9_pam_start_screenshot.png

echo "=== Setup Complete ==="