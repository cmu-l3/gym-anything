#!/bin/bash
# Setup for extract_inactive_customers
# Restores Chinook database and launches LibreOffice Base

set -e
echo "=== Setting up extract_inactive_customers task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure we start with a clean state
# setup_libreoffice_base_task handles: kill LO, restore ODB, launch, wait, dismiss dialogs, maximize
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="