#!/bin/bash
set -e
echo "=== Setting up Configure Project Region Field task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OpenProject to be ready
wait_for_openproject

# Verify initial state: Field should NOT exist
echo "Checking for pre-existing field..."
FIELD_EXISTS=$(op_rails "puts CustomField.where(name: 'Owning Region').exists?")
if [ "$FIELD_EXISTS" == "true" ]; then
    echo "WARNING: Field 'Owning Region' already exists. Attempting to clean up..."
    op_rails "CustomField.where(name: 'Owning Region').destroy_all"
fi

# Launch Firefox to the Administration > Custom Fields page
# This gives the agent a helpful starting point (Admin perspective)
launch_firefox_to "http://localhost:8080/admin/custom_fields" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="