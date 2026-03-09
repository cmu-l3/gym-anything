#!/bin/bash
set -e
echo "=== Setting up Create Form with Lookup Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent instructions:"
echo "1. Create a form named 'CustomerEntry'."
echo "2. Use a List Box for SupportRepId to show Employee names."