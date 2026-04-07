#!/bin/bash
echo "=== Setting up eco_profile_extrusion_step task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure workspace directory exists and has correct permissions
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Clean up any previous attempts
rm -f /home/ga/Documents/SolveSpace/base_4_5mm.slvs
rm -f /home/ga/Documents/SolveSpace/base_4_5mm.step
rm -f /tmp/task_result.json
rm -f /tmp/eval_base.slvs
rm -f /tmp/eval_base.step

# Verify the required sample file exists
if [ ! -f "/opt/solvespace_samples/base.slvs" ]; then
    echo "ERROR: Missing required sample file /opt/solvespace_samples/base.slvs"
    # Create a fallback rectangle if somehow missing, though install script provides it
    su - ga -c "echo '±Recipe' > /opt/solvespace_samples/base.slvs"
fi

# Kill any existing SolveSpace instances
kill_solvespace

# Launch SolveSpace with a blank canvas so the agent must use File > Open
echo "Launching SolveSpace..."
launch_solvespace ""

# Wait for application window to appear
wait_for_solvespace 30
sleep 4

# Maximize SolveSpace and position Property Browser properly
maximize_solvespace
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="