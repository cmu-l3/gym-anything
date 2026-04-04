#!/bin/bash
# pre_task hook for create_report: Start LibreOffice Base with chinook.odb open.
# The agent must create a report named 'Artist Catalog' using the Report Wizard.
echo "=== Setting up create_report task ==="

source /workspace/scripts/task_utils.sh

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

echo "=== create_report task ready ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should: click Reports in the left panel, then use 'Use Wizard to Create Report'."
