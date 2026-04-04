#!/bin/bash
set -e
echo "=== Setting up manage_user_permissions task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
# We use the standard chinook.odb which contains the HSQLDB embedded database
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

echo "=== Task setup complete ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent needs to open Tools -> SQL and execute CREATE USER / GRANT statements."