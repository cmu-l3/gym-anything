#!/bin/bash
echo "=== Setting up measure_atomic_distance task ==="

source /workspace/scripts/task_utils.sh

# Ensure PDB file exists
PDB_FILE="/home/ga/PyMOL_Data/structures/1UBQ.pdb"
if [ ! -f "$PDB_FILE" ]; then
    echo "ERROR: 1UBQ.pdb not found, downloading..."
    wget -q "https://files.rcsb.org/download/1UBQ.pdb" -O "$PDB_FILE" || true
    chown ga:ga "$PDB_FILE"
fi

# Allow X11 access
DISPLAY=:1 xhost +local: 2>/dev/null || true

# Create a startup script to load structure and show cartoon representation
cat > /tmp/pymol_task_setup.pml << ENDPML
load ${PDB_FILE}
show cartoon
ENDPML
chown ga:ga /tmp/pymol_task_setup.pml

# Launch PyMOL with the startup script
launch_pymol "/tmp/pymol_task_setup.pml"
sleep 3
maximize_pymol
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_measure_distance.png

echo "=== measure_atomic_distance task setup complete ==="
