#!/bin/bash
set -e
echo "=== Setting up Implement Loyalty Tiers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure we start with a clean database
# setup_libreoffice_base_task kills LO, restores ODB, launches LO, waits, and maximizes
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="