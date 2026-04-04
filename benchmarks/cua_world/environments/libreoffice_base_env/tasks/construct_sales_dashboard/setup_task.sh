#!/bin/bash
echo "=== Setting up construct_sales_dashboard task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file checksum to detect modifications later
md5sum /home/ga/chinook.odb > /tmp/initial_odb_checksum.txt

echo "=== Task setup complete ==="