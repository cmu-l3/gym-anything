#!/bin/bash
echo "=== Setting up Ferritin Nanocage Assembly Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1FHA (Ferritin) biological assembly
if [ ! -f "$PDB_DIR/1FHA.pdb1" ]; then
    echo "Downloading PDB:1FHA biological assembly..."
    wget -q "https://files.rcsb.org/download/1FHA.pdb1" -O "$PDB_DIR/1FHA.pdb1" 2>/dev/null || true
    wget -q "https://files.rcsb.org/download/1FHA.pdb" -O "$PDB_DIR/1FHA.pdb" 2>/dev/null || true
    chown ga:ga "$PDB_DIR"/1FHA.* 2>/dev/null || true
fi

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming check)
rm -f /home/ga/PyMOL_Data/images/ferritin_cage.png
rm -f /home/ga/PyMOL_Data/ferritin_analysis_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ferritin_start_ts

# Launch PyMOL with an empty workspace
launch_pymol

# Wait for UI stabilization and take initial screenshot
sleep 3
take_screenshot /tmp/ferritin_start_screenshot.png

echo "=== Setup Complete ==="