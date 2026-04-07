#!/bin/bash
echo "=== Setting up create_data_science_env task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# CRITICAL: Clean up any pre-existing ml_project environment
echo "Cleaning any pre-existing ml_project environment..."
su - ga -c "/home/ga/anaconda3/bin/conda env remove -n ml_project -y" 2>/dev/null || true
sleep 2

# Verify cleanup
if conda_env_exists "ml_project"; then
    echo "CRITICAL ERROR: ml_project environment still exists after cleanup!"
    su - ga -c "/home/ga/anaconda3/bin/conda env list"
    exit 1
fi
echo "Cleanup verified: ml_project environment does not exist"

# Record start time for timestamp validation
echo "$(date +%s)" > /tmp/episode_start_time
echo "Episode start time recorded: $(cat /tmp/episode_start_time)"

# Launch Navigator directly on the Environments tab
navigate_to_tab "environments"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "1. Click 'Create' button to create a new environment"
echo "2. Name it 'ml_project' with Python 3.11"
echo "3. Install numpy, pandas, scikit-learn, matplotlib via package manager"
