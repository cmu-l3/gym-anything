#!/bin/bash
# pre_task hook for create_form: Start LibreOffice Base with chinook.odb open.
# The agent must create a form named 'Customer Entry Form' using the Form Wizard.
echo "=== Setting up create_form task ==="

source /workspace/scripts/task_utils.sh

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

echo "=== create_form task ready ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should: click Forms in the left panel, then use 'Use Wizard to Create Form'."
