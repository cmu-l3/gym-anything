#!/bin/bash
set -e
echo "=== Setting up update_customer_info task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Reset the environment: kill LO, restore ODB, launch
setup_libreoffice_base_task "/home/ga/chinook.odb"

# Calculate initial checksum of the ODB file to detect "no change"
md5sum /home/ga/chinook.odb | awk '{print $1}' > /tmp/initial_odb_hash.txt

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="