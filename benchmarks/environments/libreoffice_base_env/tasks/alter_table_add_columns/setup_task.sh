#!/bin/bash
set -e
echo "=== Setting up alter_table_add_columns task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Reset environment: Kill LO, restore fresh ODB, launch Base
# This function handles the heavy lifting of window management
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file state
INITIAL_SIZE=$(stat -c%s /home/ga/chinook.odb 2>/dev/null || echo "0")
echo "$INITIAL_SIZE" > /tmp/initial_odb_size.txt

# Extract initial schema for comparison
# HSQLDB stores the schema in 'database/script' inside the ODB zip
echo "Extracting initial schema..."
unzip -p /home/ga/chinook.odb database/script > /tmp/initial_schema.txt 2>/dev/null || echo "Failed to extract schema"

# Take screenshot of the initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="