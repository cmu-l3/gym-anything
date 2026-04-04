#!/bin/bash
# pre_task hook for implement_mood_tagging
echo "=== Setting up implement_mood_tagging task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Full setup: kill any LO instance, restore fresh ODB, launch, wait, dismiss dialogs
setup_libreoffice_base_task /home/ga/chinook.odb

# Maximize window again to be sure
maximize_libreoffice

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== implement_mood_tagging task ready ==="
echo "LibreOffice Base is open with chinook.odb."
echo "Agent should: Create Mood and TrackMood tables, then populate them."