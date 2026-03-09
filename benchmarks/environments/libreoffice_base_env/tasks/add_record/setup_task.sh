#!/bin/bash
# pre_task hook for add_record: Start LibreOffice Base with chinook.odb open.
# The agent must open the Customer table and add a new record (customer #60).
echo "=== Setting up add_record task ==="

source /workspace/scripts/task_utils.sh

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

echo "=== add_record task ready ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should: double-click the Customer table to open it in datasheet view,"
echo "then scroll to the bottom and add a new row with CustomerId=60."
