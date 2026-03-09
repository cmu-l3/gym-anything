#!/bin/bash
echo "=== Setting up query_long_rock_tracks task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Full setup: kill LO, restore fresh ODB, launch, wait, dismiss dialogs, maximize
# This ensures a clean state with the Chinook database loaded
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file modification time to detect saves
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

echo "=== Task setup complete ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should create 'DeepCutsPlaylist' query."