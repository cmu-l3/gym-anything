#!/bin/bash
set -e
echo "=== Setting up DHS CFATS Security Screening Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the input list on the Desktop
cat > /home/ga/Desktop/cfats_audit_list.txt << 'EOF'
CHEMICAL SECURITY AUDIT LIST
============================
Please screen the following chemicals against DHS CFATS regulations using CAMEO Chemicals:

1. Chlorine
2. Propane
3. Ammonium Nitrate
4. Triethanolamine
5. Sodium Chloride
6. Hydrogen Peroxide (Concentration > 35%)
EOF
chmod 644 /home/ga/Desktop/cfats_audit_list.txt
chown ga:ga /home/ga/Desktop/cfats_audit_list.txt

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Remove any pre-existing output file to prevent false positives
rm -f /home/ga/Documents/cfats_security_report.csv

# Launch Firefox to CAMEO Chemicals
launch_firefox_to_url "https://cameochemicals.noaa.gov/" "ga"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="