#!/bin/bash
echo "=== Setting up T4 Lysozyme Hydrophobic Cavity Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Pre-download the required PDB files to ensure network reliability
for pdb in 2LZM 4W52; do
    if [ ! -f "$PDB_DIR/${pdb}.pdb" ]; then
        echo "Downloading PDB:${pdb}..."
        wget -q "https://files.rcsb.org/download/${pdb}.pdb" -O "$PDB_DIR/${pdb}.pdb" 2>/dev/null || true
        chown ga:ga "$PDB_DIR/${pdb}.pdb" 2>/dev/null || true
    fi
done

# Ensure output directories exist and are owned by the agent user
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete any stale output files BEFORE recording the timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/t4_cavity_superposition.png
rm -f /home/ga/PyMOL_Data/t4_cavity_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/t4_cavity_start_ts

# Launch an empty PyMOL session (agent must load the structures themselves)
launch_pymol

# Give PyMOL a moment to initialize and capture the initial state screenshot
sleep 2
take_screenshot /tmp/t4_cavity_start_screenshot.png

echo "=== Setup Complete ==="