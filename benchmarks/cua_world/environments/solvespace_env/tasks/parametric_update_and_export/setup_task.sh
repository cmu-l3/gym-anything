#!/bin/bash
set -e
echo "=== Setting up parametric_update_and_export task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure workspace and target directories are clean
mkdir -p /home/ga/Documents/SolveSpace/
rm -rf /home/ga/Documents/SolveSpace/production/
mkdir -p /home/ga/Documents/SolveSpace/production/
chown -R ga:ga /home/ga/Documents/SolveSpace

# Verify the real source file exists
if [ ! -f "/opt/solvespace_samples/base.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/base.slvs not found"
    exit 1
fi

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with the target file
echo "Launching SolveSpace with base.slvs..."
launch_solvespace "/opt/solvespace_samples/base.slvs"

# Wait for SolveSpace to fully load
wait_for_solvespace 30
sleep 4

# Maximize the window
maximize_solvespace
sleep 1

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="