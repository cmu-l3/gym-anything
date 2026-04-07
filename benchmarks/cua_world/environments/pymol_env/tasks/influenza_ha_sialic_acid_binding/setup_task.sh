#!/bin/bash
echo "=== Setting up Influenza HA Sialic Acid Binding Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
mkdir -p /home/ga/PyMOL_Data/structures
chown -R ga:ga /home/ga/PyMOL_Data

# Pre-cache the PDB in case fetch fails due to transient network issues
if [ ! -f "/home/ga/PyMOL_Data/structures/1RVZ.pdb" ]; then
    wget -q "https://files.rcsb.org/download/1RVZ.pdb" -O /home/ga/PyMOL_Data/structures/1RVZ.pdb 2>/dev/null || true
    chown ga:ga /home/ga/PyMOL_Data/structures/1RVZ.pdb
fi

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/ha_receptor_binding.png
rm -f /home/ga/PyMOL_Data/ha_sialic_acid_contacts.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/ha_sialic_acid_start_ts

# Launch PyMOL EMPTY (Agent must fetch or load the structure itself)
launch_pymol

# Take initial screenshot
sleep 2
take_screenshot /tmp/ha_sialic_acid_start_screenshot.png

echo "=== Setup Complete ==="