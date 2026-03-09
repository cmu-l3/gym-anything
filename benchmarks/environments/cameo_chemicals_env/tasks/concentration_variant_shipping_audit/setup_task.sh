#!/bin/bash
# setup_task.sh - Pre-task hook for concentration_variant_shipping_audit
set -e

echo "=== Setting up Concentration Variant Shipping Audit Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the Manifest file on the Desktop
cat > /home/ga/Desktop/manifest_list.txt << EOF
SHIPPING MANIFEST AUDIT LIST
============================
Please look up UN Number and DOT Labels for:

1. Ammonia, Anhydrous
2. Ammonia, 25% Solution
3. Hydrogen Peroxide, 50% Solution
4. Hydrogen Peroxide, 15% Solution
5. Nitric Acid, Red Fuming
EOF
chown ga:ga /home/ga/Desktop/manifest_list.txt

# Remove any previous output file to prevent gaming
rm -f /home/ga/Desktop/shipping_audit.csv
rm -f /tmp/task_result.json

# Kill any existing Firefox instances
kill_firefox ga

# Launch Firefox to CAMEO Chemicals
launch_firefox_to_url "https://cameochemicals.noaa.gov/" ga

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="