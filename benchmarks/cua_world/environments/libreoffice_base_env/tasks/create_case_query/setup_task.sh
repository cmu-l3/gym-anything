#!/bin/bash
set -e
echo "=== Setting up create_case_query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Calculate initial hash of the ODB file to detect "do nothing" agents
md5sum /home/ga/chinook.odb | awk '{print $1}' > /tmp/initial_odb_hash.txt

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
# This ensures the agent starts with a clean state
setup_libreoffice_base_task /home/ga/chinook.odb

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="