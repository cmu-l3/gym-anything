#!/bin/bash
set -e
echo "=== Setting up create_server_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up: Remove the template if it already exists from a previous run
# Templates are files in /etc/webmin/virtual-server/templates/
# We search for the file containing "name=FastWeb Static" and delete it
echo "Checking for existing 'FastWeb Static' template..."
grep -l "^name=FastWeb Static$" /etc/webmin/virtual-server/templates/* 2>/dev/null | while read -r template_file; do
    echo "Removing stale template file: $template_file"
    rm -f "$template_file"
done

# Also remove from the config list of templates if referenced
# (Virtualmin maintains a list, but deleting the file usually forces a refresh or invalidates it)
# A full reload of Webmin might be needed if we were being very strict, 
# but deleting the file is usually sufficient for the UI to not show it after a refresh.

# 2. Ensure Virtualmin is running and accessible
ensure_virtualmin_ready

# 3. Navigate to the System Settings area (or just Dashboard to let agent find it)
# We'll start at the dashboard to require the agent to find "System Settings"
navigate_to "https://localhost:10000/virtual-server/index.cgi"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="