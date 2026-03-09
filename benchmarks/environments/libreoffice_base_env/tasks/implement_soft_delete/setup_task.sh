#!/bin/bash
set -e
echo "=== Setting up implement_soft_delete task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Use the standard helper to setup LibreOffice Base with Chinook
# This kills existing instances, restores the ODB, launches LO, and maximizes
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="