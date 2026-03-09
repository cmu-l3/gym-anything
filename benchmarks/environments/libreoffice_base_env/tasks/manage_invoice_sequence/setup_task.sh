#!/bin/bash
echo "=== Setting up manage_invoice_sequence task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure we start with a fresh, known state
echo "Restoring database..."
restore_chinook_odb

# Launch LibreOffice Base
launch_libreoffice_base "/home/ga/chinook.odb"

# Wait for window, dismiss dialogs, maximize
wait_for_libreoffice_base 45
dismiss_dialogs
maximize_libreoffice

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="