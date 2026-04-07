#!/bin/bash
echo "=== Setting up GPCR TM Helix Analysis Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Pre-download 2RH1 (human β2-adrenergic receptor) to avoid network issues during evaluation
# But DO NOT load it into PyMOL automatically. The agent must load it.
if [ ! -f "$PDB_DIR/2RH1.pdb" ]; then
    echo "Downloading PDB:2RH1..."
    wget -q "https://files.rcsb.org/download/2RH1.pdb" -O "$PDB_DIR/2RH1.pdb" 2>/dev/null || true
    chown ga:ga "$PDB_DIR/2RH1.pdb"
fi
echo "PDB:2RH1 available at $PDB_DIR/2RH1.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Critical for Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/gpcr_tm_helices.png
rm -f /home/ga/PyMOL_Data/gpcr_binding_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/gpcr_task_start_ts

# Launch PyMOL empty
launch_pymol

# Wait for window and take initial screenshot
sleep 3
take_screenshot /tmp/gpcr_task_start_screenshot.png

echo "=== Setup Complete ==="