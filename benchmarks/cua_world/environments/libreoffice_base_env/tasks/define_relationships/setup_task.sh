#!/bin/bash
set -e
echo "=== Setting up define_relationships task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Kill any existing LibreOffice instances
kill_libreoffice

# 2. Restore a fresh copy of the Chinook database
# This ensures no relationships exist at start
restore_chinook_odb

# 3. Calculate initial hash of the ODB file to detect modification later
md5sum /home/ga/chinook.odb | awk '{print $1}' > /tmp/initial_odb_hash.txt
echo "Initial ODB hash: $(cat /tmp/initial_odb_hash.txt)"

# 4. Launch LibreOffice Base with the database
launch_libreoffice_base /home/ga/chinook.odb

# 5. Wait for window to appear
wait_for_libreoffice_base 45

# 6. Dismiss any first-run or migration dialogs
dismiss_dialogs

# 7. Maximize the window for visibility
maximize_libreoffice

# 8. Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="