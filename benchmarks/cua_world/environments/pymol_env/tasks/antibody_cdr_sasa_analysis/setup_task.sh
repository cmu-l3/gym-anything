#!/bin/bash
echo "=== Setting up Antibody CDR SASA Analysis ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Pre-download 1N8Z to avoid network flakiness if the agent uses `load` instead of `fetch`
if [ ! -f "$PDB_DIR/1N8Z.pdb" ]; then
    echo "Downloading PDB:1N8Z (Herceptin Fab)..."
    wget -q "https://files.rcsb.org/download/1N8Z.pdb" -O "$PDB_DIR/1N8Z.pdb" 2>/dev/null
    chown ga:ga "$PDB_DIR/1N8Z.pdb"
fi

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/PyMOL_Data/images/herceptin_cdrs.png
rm -f /home/ga/PyMOL_Data/cdr_sasa_report.txt

# Record task start timestamp (integer seconds) for anti-gaming checks
date +%s > /tmp/cdr_sasa_start_ts

# Launch PyMOL with empty session (agent must fetch/load the structure)
launch_pymol

sleep 2
take_screenshot /tmp/cdr_sasa_start_screenshot.png

echo "=== Setup Complete ==="