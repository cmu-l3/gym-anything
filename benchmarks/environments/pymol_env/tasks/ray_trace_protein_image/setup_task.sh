#!/bin/bash
echo "=== Setting up ray_trace_protein_image task ==="

source /workspace/scripts/task_utils.sh

# Ensure PDB file exists
PDB_FILE="/home/ga/PyMOL_Data/structures/1CRN.pdb"
if [ ! -f "$PDB_FILE" ]; then
    echo "ERROR: 1CRN.pdb not found, downloading..."
    wget -q "https://files.rcsb.org/download/1CRN.pdb" -O "$PDB_FILE" || true
    chown ga:ga "$PDB_FILE"
fi

# Ensure output directory exists
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data/images

# Remove any previous output to ensure clean state
rm -f /home/ga/PyMOL_Data/images/crambin_raytrace.png

# Allow X11 access
DISPLAY=:1 xhost +local: 2>/dev/null || true

# Launch PyMOL with the crambin structure
launch_pymol_with_file "$PDB_FILE"

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start_ray_trace.png

echo "=== ray_trace_protein_image task setup complete ==="
