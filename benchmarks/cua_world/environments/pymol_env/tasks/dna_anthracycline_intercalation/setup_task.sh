#!/bin/bash
echo "=== Setting up DNA Anthracycline Intercalation Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 1D12 (DNA-Doxorubicin complex)
if [ ! -f "$PDB_DIR/1D12.pdb" ]; then
    echo "Downloading PDB:1D12 (DNA-Doxorubicin complex)..."
    wget -q "https://files.rcsb.org/download/1D12.pdb" -O "$PDB_DIR/1D12.pdb" 2>/dev/null
    if [ ! -s "$PDB_DIR/1D12.pdb" ]; then
        echo "ERROR: Failed to download 1D12.pdb"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/1D12.pdb"
fi
echo "PDB:1D12 available at $PDB_DIR/1D12.pdb"

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (Anti-gaming)
rm -f /home/ga/PyMOL_Data/images/dna_intercalation.png
rm -f /home/ga/PyMOL_Data/intercalation_report.txt

# Record task start timestamp for file modification checks
date +%s > /tmp/dna_intercalation_start_ts

# Launch PyMOL with the target structure
launch_pymol_with_file "$PDB_DIR/1D12.pdb"

sleep 2
take_screenshot /tmp/dna_intercalation_start_screenshot.png

echo "=== Setup Complete ==="