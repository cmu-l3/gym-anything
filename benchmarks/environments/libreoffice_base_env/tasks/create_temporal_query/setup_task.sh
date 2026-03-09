#!/bin/bash
set -e
echo "=== Setting up create_temporal_query task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Full setup: kill LO, restore ODB, launch, wait, dismiss dialogs, maximize
# This ensures a clean state with 'chinook.odb' loaded
setup_libreoffice_base_task /home/ga/chinook.odb

# Take screenshot of initial state
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Verify screenshot capture
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot."
fi

echo "=== Task setup complete ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should create a query named 'MonthlyRevenueAnalysis'."