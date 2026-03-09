#!/bin/bash
set -e
echo "=== Setting up Standardize Artist Names Task ==="

# Source shared utilities for LibreOffice Base
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Reset the database to a fresh state (Standard Chinook data)
# This function handles killing LO, restoring the ODB file, launching LO,
# waiting for the window, dismissing dialogs, and maximizing.
setup_libreoffice_base_task /home/ga/chinook.odb

# Record initial file timestamp for comparison later
stat -c %Y /home/ga/chinook.odb > /tmp/initial_odb_mtime.txt

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="