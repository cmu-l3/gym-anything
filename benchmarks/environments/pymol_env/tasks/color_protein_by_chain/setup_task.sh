#!/bin/bash
echo "=== Setting up color_protein_by_chain task ==="

source /workspace/scripts/task_utils.sh

# Ensure PDB file exists
PDB_FILE="/home/ga/PyMOL_Data/structures/4HHB.pdb"
if [ ! -f "$PDB_FILE" ]; then
    echo "ERROR: 4HHB.pdb not found, downloading..."
    wget -q "https://files.rcsb.org/download/4HHB.pdb" -O "$PDB_FILE" || true
    chown ga:ga "$PDB_FILE"
fi

# Allow X11 access
DISPLAY=:1 xhost +local: 2>/dev/null || true

# Launch PyMOL with the hemoglobin structure
launch_pymol_with_file "$PDB_FILE"

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start_color_protein.png

echo "=== color_protein_by_chain task setup complete ==="
