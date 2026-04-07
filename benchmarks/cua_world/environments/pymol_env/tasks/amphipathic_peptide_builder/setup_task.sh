#!/bin/bash
echo "=== Setting up Antimicrobial Peptide Builder Task ==="

source /workspace/scripts/task_utils.sh

# Ensure output directories exist
mkdir -p /home/ga/PyMOL_Data/images
chown -R ga:ga /home/ga/PyMOL_Data

# Delete stale outputs BEFORE recording timestamp (anti-gaming)
rm -f /home/ga/PyMOL_Data/images/magainin_amphipathic.png
rm -f /home/ga/PyMOL_Data/magainin_ideal.pdb
rm -f /home/ga/PyMOL_Data/peptide_report.txt

# Record task start timestamp (integer seconds)
date +%s > /tmp/peptide_builder_start_ts

# Launch PyMOL with an empty session
launch_pymol

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/peptide_builder_start_screenshot.png

echo "=== Setup Complete ==="