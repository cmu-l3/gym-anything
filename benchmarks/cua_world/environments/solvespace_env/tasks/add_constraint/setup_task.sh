#!/bin/bash
echo "=== Setting up add_constraint task ==="

source /workspace/scripts/task_utils.sh

# Remove any previous output file
rm -f /home/ga/Documents/SolveSpace/side_constrained.slvs

# Ensure workspace directory exists
mkdir -p /home/ga/Documents/SolveSpace
chown ga:ga /home/ga/Documents/SolveSpace

# Verify the source file exists (2D sketch with diagonal line, no H constraint)
if [ ! -f "/opt/solvespace_samples/line_to_constrain.slvs" ]; then
    echo "ERROR: /opt/solvespace_samples/line_to_constrain.slvs not found"
    exit 1
fi

FSIZE=$(stat -c%s "/opt/solvespace_samples/line_to_constrain.slvs")
echo "Source file: /opt/solvespace_samples/line_to_constrain.slvs ($FSIZE bytes)"

# Copy to the workspace as the starting file
cp /opt/solvespace_samples/line_to_constrain.slvs /home/ga/Documents/SolveSpace/line_to_constrain.slvs
chown ga:ga /home/ga/Documents/SolveSpace/line_to_constrain.slvs

# Kill any existing SolveSpace instance
kill_solvespace

# Launch SolveSpace with the line_to_constrain.slvs file
launch_solvespace "/home/ga/Documents/SolveSpace/line_to_constrain.slvs"

# Wait for SolveSpace to fully load the file
echo "Waiting for SolveSpace to load line_to_constrain.slvs..."
wait_for_solvespace 30
sleep 6

# Maximize the window
maximize_solvespace
sleep 1

# Take a screenshot to confirm start state
take_screenshot /tmp/add_constraint_start.png
echo "Task start state screenshot saved to /tmp/add_constraint_start.png"

echo "=== add_constraint task setup complete ==="
echo "Agent should see: SolveSpace with line_to_constrain.slvs loaded (2D sketch with diagonal line)"
echo "Goal: Add horizontal constraint to the line, save as ~/Documents/SolveSpace/side_constrained.slvs"
