#!/bin/bash
# pre_task hook for run_query: Start LibreOffice Base with chinook.odb open.
# The agent must create a SQL query named 'LongTracks'.
echo "=== Setting up run_query task ==="

source /workspace/scripts/task_utils.sh

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

echo "=== run_query task ready ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should: click Queries in the left panel, then use 'Create Query in SQL View'."
