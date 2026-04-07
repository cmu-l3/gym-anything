#!/bin/bash
echo "=== Setting up MHC Peptide Groove Analysis Task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup Data Directories
PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"
mkdir -p "/home/ga/PyMOL_Data/images"

# 2. Download 1AKJ (HLA-A2 with Tax peptide)
if [ ! -f "$PDB_DIR/1AKJ.pdb" ]; then
    echo "Downloading PDB:1AKJ..."
    wget -q "https://files.rcsb.org/download/1AKJ.pdb" -O "$PDB_DIR/1AKJ.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1AKJ.pdb" ]; then
        echo "ERROR: Failed to download 1AKJ.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1AKJ.pdb"
fi
echo "PDB:1AKJ available at $PDB_DIR/1AKJ.pdb"

# 3. Clean up any stale outputs (Anti-Gaming)
rm -f /home/ga/PyMOL_Data/images/mhc_peptide.png
rm -f /home/ga/PyMOL_Data/mhc_groove_report.txt
rm -f /tmp/mhc_peptide_result.json

# Ensure correct permissions
chown -R ga:ga /home/ga/PyMOL_Data

# 4. Record task start timestamp (integer seconds)
date +%s > /tmp/task_start_time.txt

# 5. Launch PyMOL clean (as requested by task starting state)
launch_pymol

# Wait for PyMOL window to initialize, focus it, and take a screenshot
sleep 4
focus_pymol
maximize_pymol
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="