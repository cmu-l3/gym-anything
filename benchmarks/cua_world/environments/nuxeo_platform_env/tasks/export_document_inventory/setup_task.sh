#!/bin/bash
set -e
echo "=== Setting up export_document_inventory task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Nuxeo is running and ready
wait_for_nuxeo 120

# Ensure the Projects workspace exists and has content
# (The environment setup usually creates this, but we verify here)
echo "Verifying Projects workspace content..."
if ! doc_exists "/default-domain/workspaces/Projects"; then
    echo "Creating Projects workspace..."
    create_doc_if_missing "/default-domain/workspaces" "Workspace" "Projects" "Projects" "Active project documents"
fi

# Ensure specific documents exist to guarantee non-empty result
# We need at least one File and one Note for a good test
if ! doc_exists "/default-domain/workspaces/Projects/Annual-Report-2023"; then
    # Create a dummy if the real file setup failed (fallback)
    create_doc_if_missing "/default-domain/workspaces/Projects" "File" "Annual-Report-2023" "Annual Report 2023" "Fallback doc"
fi

if ! doc_exists "/default-domain/workspaces/Projects/Q3-Status-Report"; then
    create_doc_if_missing "/default-domain/workspaces/Projects" "Note" "Q3-Status-Report" "Q3 Status Report" "Fallback note"
fi

# Ensure output directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous run artifacts (CRITICAL for valid verification)
rm -f /home/ga/Documents/project_inventory.json

# Launch tools for the agent
# 1. Open Terminal (since this is an API/scripting task)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    sudo -u ga DISPLAY=:1 gnome-terminal --geometry=100x30+100+100 &
    sleep 2
fi

# 2. Open Firefox to the API documentation or Workspace view
# This gives the agent a way to explore the structure visually if they want
open_nuxeo_url "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects" 8
nuxeo_login

# Maximize Firefox for visibility
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus Terminal initially as this is a coding/CLI task
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="