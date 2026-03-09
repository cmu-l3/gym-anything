#!/bin/bash
set -e
echo "=== Setting up Rail Transport STCC Lookup Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Desktop
sudo -u ga mkdir -p /home/ga/Documents

# Create the input list of chemicals
cat > /tmp/rail_shipment_list.txt << EOF
Chlorine
Vinyl Chloride, stabilized
Styrene monomer, stabilized
Propane
Ammonia, anhydrous
EOF

# Move to Desktop with correct permissions
cp /tmp/rail_shipment_list.txt /home/ga/Desktop/rail_shipment_list.txt
chown ga:ga /home/ga/Desktop/rail_shipment_list.txt
chmod 644 /home/ga/Desktop/rail_shipment_list.txt

# Remove any existing output file to ensure fresh creation
rm -f /home/ga/Documents/rail_manifest.json

# Launch Firefox to CAMEO Chemicals
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="