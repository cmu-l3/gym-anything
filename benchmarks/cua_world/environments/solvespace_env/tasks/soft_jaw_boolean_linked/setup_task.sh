#!/bin/bash
echo "=== Setting up soft_jaw_boolean_linked task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Remove any previous artifacts
rm -f /home/ga/Documents/SolveSpace/soft_jaw_fixture.slvs
rm -f /home/ga/Documents/SolveSpace/soft_jaw_fixture.step
rm -f /tmp/task_result.json

# Verify the real source file exists (downloaded during install)
if [ ! -f "/opt/solvespace_samples/divider.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/divider.slvs not found"
    exit 1
fi

FSIZE=$(stat -c%s "/opt/solvespace_samples/divider.slvs")
echo "Target imported part verified: /opt/solvespace_samples/divider.slvs ($FSIZE bytes)"

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with an empty canvas
launch_solvespace ""

# Wait for SolveSpace to fully load
echo "Waiting for SolveSpace to start..."
wait_for_solvespace 30
sleep 5

# Maximize the window so agent has full workspace
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/task_initial.png
echo "Task start state screenshot saved to /tmp/task_initial.png"

echo "=== setup_task complete ==="
echo "Agent should see: SolveSpace with blank canvas"
echo "Goal: Model 150x80x15 block, import divider.slvs, set boolean difference, export to STEP"