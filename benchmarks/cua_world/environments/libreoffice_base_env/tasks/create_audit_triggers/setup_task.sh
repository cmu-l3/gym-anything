#!/bin/bash
echo "=== Setting up create_audit_triggers task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial size of the ODB file
stat -c %s /home/ga/chinook.odb > /tmp/initial_odb_size.txt

echo "=== Task setup complete ==="