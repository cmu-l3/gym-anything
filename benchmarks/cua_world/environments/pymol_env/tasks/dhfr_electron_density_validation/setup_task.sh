#!/bin/bash
echo "=== Setting up DHFR Electron Density Validation Task ==="

source /workspace/scripts/task_utils.sh

PDB_DIR="/home/ga/PyMOL_Data/structures"
mkdir -p "$PDB_DIR"
mkdir -p "/home/ga/PyMOL_Data/images"
mkdir -p "/home/ga/PyMOL_Data/sessions"

# Pre-download PDB and map files to provide a robust fallback in case of PyMOL fetch network issues
echo "Downloading PDB:1RX2..."
wget -q "https://files.rcsb.org/download/1RX2.pdb" -O "$PDB_DIR/1RX2.pdb" 2>/dev/null || true

echo "Downloading 2Fo-Fc map for 1RX2..."
wget -q "https://edmaps.rcsb.org/maps/1rx2_2fofc.ccp4" -O "$PDB_DIR/1rx2_2fofc.ccp4" 2>/dev/null || true

chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/dhfr_mtx_density.png
rm -f /home/ga/PyMOL_Data/sessions/dhfr_mtx_density.pse
rm -f /home/ga/PyMOL_Data/dhfr_mtx_report.txt

# Record task start timestamp
date +%s > /tmp/dhfr_mtx_start_ts

# Launch PyMOL with an empty session (agent must perform loading)
launch_pymol

# Wait for PyMOL and take initial screenshot
sleep 3
take_screenshot /tmp/dhfr_mtx_start_screenshot.png

echo "=== Setup Complete ==="