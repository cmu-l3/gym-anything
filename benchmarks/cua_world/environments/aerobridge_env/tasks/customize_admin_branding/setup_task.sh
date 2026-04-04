#!/bin/bash
# setup_task.sh — pre_task hook for customize_admin_branding
# Ensures Aerobridge is running and records initial state.

echo "=== Setting up customize_admin_branding task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Wait for Aerobridge server to be ready
echo "Waiting for Aerobridge server..."
wait_for_aerobridge 60 || echo "WARNING: server may not be ready"

# 3. Ensure we are starting from a clean state (default Django branding)
# We don't want to overwrite if it's already customized by a previous run of this specific task,
# but for a fresh env it should be standard.
# We'll rely on the agent to make the changes.

# 4. Launch Firefox to the admin login page so the agent sees the target immediately
echo "Launching Firefox..."
launch_firefox "http://localhost:8000/admin/login/"

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="