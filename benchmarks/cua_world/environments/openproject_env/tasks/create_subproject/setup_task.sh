#!/bin/bash
# Setup for create_subproject task
# Ensures OpenProject is running, user is logged in, and Firefox shows DevOps Automation project

set -e
echo "=== Setting up create_subproject task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Wait for OpenProject to be ready
wait_for_openproject

# Ensure the "DevOps Automation" project exists (it should from seeding)
echo "Verifying parent project existence..."
DEVOPS_EXISTS=$(op_rails "puts Project.where(identifier: 'devops-automation').exists?")
if [[ "$DEVOPS_EXISTS" != *"true"* ]]; then
    echo "ERROR: DevOps Automation project not found! Seeding may have failed."
    exit 1
fi

# Make sure there's no pre-existing project with our target identifier (clean state)
echo "Cleaning up any stale project..."
op_rails "p = Project.find_by(identifier: 'cicd-pipeline-hardening'); p.destroy! if p; puts 'Cleaned up stale project'" 2>/dev/null || true

# Launch Firefox to the DevOps Automation project overview
DEVOPS_URL="${OP_URL}/projects/devops-automation"
echo "Launching Firefox to: $DEVOPS_URL"
launch_firefox_to "$DEVOPS_URL" 8

# Maximize and ensure focus
maximize_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png
echo "Initial screenshot saved to /tmp/task_initial_state.png"

echo "=== Task setup complete ==="