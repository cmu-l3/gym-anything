#!/bin/bash
set -e
echo "=== Setting up export_host_visitor_history task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any previous run artifacts
rm -f /home/ga/Documents/james_wilson_visitors.csv 2>/dev/null || true

# Ensure Jolly Lobby Track is running
# This function (from task_utils.sh) handles launching and waiting for the window
launch_lobbytrack

# Wait for the application to be fully ready and focused
sleep 5
WID=$(xdotool search --name "Lobby Track" | head -1)
if [ -n "$WID" ]; then
    xdotool windowactivate "$WID"
    # Ensure window is maximized for best VLM visibility
    wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Create a dummy "ground truth" reference for the verifier
# In a real scenario, this would come from the database. 
# Here we define what we expect to find in the export based on the known seed data.
# We assume the environment has been seeded with standard demo data where James Wilson has visitors.
cat > /tmp/ground_truth_criteria.json << EOF
{
    "target_host": "James Wilson",
    "must_contain": ["James Wilson"],
    "must_not_contain": ["Sarah Connor", "Robert Smith"]
}
EOF

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="