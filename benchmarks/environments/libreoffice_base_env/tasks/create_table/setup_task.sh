#!/bin/bash
# pre_task hook for create_table: Start LibreOffice Base with chinook.odb open.
# The agent must create a new table named 'Promotions' using Table Design view.
echo "=== Setting up create_table task ==="

source /workspace/scripts/task_utils.sh

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

echo "=== create_table task ready ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should: click Tables in the left panel, then use 'Create Table in Design View'."
