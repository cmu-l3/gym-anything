#!/bin/bash
echo "=== Setting up Collagen Osteogenesis Imperfecta Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1CAG (Mutant collagen peptide)
if [ ! -f "$PDB_DIR/1CAG.pdb" ]; then
    echo "Downloading PDB:1CAG (Collagen Gly->Ala mutant)..."
    wget -q "https://files.rcsb.org/download/1CAG.pdb" -O "$PDB_DIR/1CAG.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1CAG.pdb" ]; then
        echo "ERROR: Failed to download 1CAG.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1CAG.pdb"
fi
echo "PDB:1CAG available at $PDB_DIR/1CAG.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/collagen_mutation.png
rm -f /home/ga/PyMOL_Data/collagen_clash_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/collagen_task_start_ts

# Launch PyMOL with the structure
launch_pymol_with_file "$PDB_DIR/1CAG.pdb"

# Wait for UI to stabilize and take initial screenshot
sleep 3
take_screenshot /tmp/collagen_task_start_screenshot.png

echo "=== Setup Complete ==="