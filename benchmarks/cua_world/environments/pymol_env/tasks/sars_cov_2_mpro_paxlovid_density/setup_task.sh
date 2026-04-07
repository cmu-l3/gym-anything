#!/bin/bash
echo "=== Setting up Paxlovid Electron Density Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"

# Download 7VH8 PDB
if [ ! -f "$PDB_DIR/7vh8.pdb" ]; then
    echo "Downloading PDB:7VH8..."
    wget -q "https://files.rcsb.org/download/7VH8.pdb" -O "$PDB_DIR/7vh8.pdb" 2>/dev/null
    chown ga:ga "$PDB_DIR/7vh8.pdb"
fi

# Download 7VH8 2Fo-Fc CCP4 Map
# Provide PDBe fallback in case the RCSB EDS map server is temporarily down
if [ ! -f "$PDB_DIR/7vh8_2fofc.ccp4" ]; then
    echo "Downloading electron density map for 7VH8..."
    wget -q "https://edmaps.rcsb.org/maps/7vh8_2fofc.ccp4" -O "$PDB_DIR/7vh8_2fofc.ccp4" 2>/dev/null || \
    wget -q "https://www.ebi.ac.uk/pdbe/coordinates/files/7vh8.ccp4" -O "$PDB_DIR/7vh8_2fofc.ccp4" 2>/dev/null
    
    if [ ! -s "$PDB_DIR/7vh8_2fofc.ccp4" ]; then
        echo "ERROR: Failed to download 7vh8_2fofc.ccp4"
        exit 1
    fi
    chown ga:ga "$PDB_DIR/7vh8_2fofc.ccp4"
fi

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/paxlovid_density.png
rm -f /home/ga/PyMOL_Data/paxlovid_density_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/paxlovid_density_start_ts

# Launch PyMOL loading both the structure and the map
launch_pymol "$PDB_DIR/7vh8.pdb" "$PDB_DIR/7vh8_2fofc.ccp4"

sleep 3
maximize_pymol
sleep 1

# Capture initial verification screenshot
take_screenshot /tmp/paxlovid_density_start_screenshot.png

echo "=== Setup Complete ==="