#!/bin/bash
echo "=== Setting up create_virtual_server task ==="

source /workspace/scripts/task_utils.sh

# Remove target domain if it exists from a previous run
if virtualmin_domain_exists "newclient.test" 2>/dev/null; then
    echo "WARNING: newclient.test already exists, removing it..."
    virtualmin delete-domain --domain newclient.test --yes 2>&1 | tail -3 || true
    sleep 3
fi

# Ensure Virtualmin is accessible in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to the "Create Virtual Server" page
# domain_form.cgi is the correct Virtualmin 8.x URL for creating a new top-level virtual server
navigate_to "https://localhost:10000/virtual-server/domain_form.cgi"
sleep 5

take_screenshot /tmp/create_virtual_server_start.png
echo "=== create_virtual_server task setup complete ==="
echo "Agent should see the Create Virtual Server form in Firefox."
