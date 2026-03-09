#!/bin/bash
set -e
echo "=== Setting up Export Risk Register task ==="

source /workspace/scripts/task_utils.sh

# 1. Clear Downloads directory to ensure we identify the NEW file correctly
echo "Cleaning Downloads directory..."
rm -rf /home/ga/Downloads/*
mkdir -p /home/ga/Downloads

# 2. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 3. Ensure Firefox is running and logged into Eramba
# We navigate to the Dashboard to force the agent to find the Risk module
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="