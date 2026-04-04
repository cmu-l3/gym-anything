#!/bin/bash
# Setup for implement_qc_workflow
set -e

echo "=== Setting up implement_qc_workflow task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for file timestamp verification)
date +%s > /tmp/task_start_time.txt

# Record initial file hash to detect if save happened
md5sum /home/ga/chinook.odb > /tmp/initial_odb_hash.txt 2>/dev/null || echo "0" > /tmp/initial_odb_hash.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="