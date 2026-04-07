#!/bin/bash
echo "=== Setting up install_package_from_channel task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# CRITICAL: Remove seaborn from base environment if present
echo "Cleaning any pre-existing seaborn installation..."
su - ga -c "/home/ga/anaconda3/bin/conda remove -n base seaborn -y" 2>/dev/null || true
sleep 2

# Also remove conda-forge channel if present to start fresh
su - ga -c "/home/ga/anaconda3/bin/conda config --remove channels conda-forge" 2>/dev/null || true
sleep 1

# Verify cleanup
if package_installed_in_env "base" "seaborn"; then
    echo "WARNING: seaborn still installed, trying pip uninstall..."
    su - ga -c "/home/ga/anaconda3/bin/pip uninstall seaborn -y" 2>/dev/null || true
fi

echo "Cleanup done. Current channels:"
su - ga -c "/home/ga/anaconda3/bin/conda config --show channels" 2>/dev/null || true

# Record start time
echo "$(date +%s)" > /tmp/episode_start_time
echo "Episode start time recorded: $(cat /tmp/episode_start_time)"

# Launch Navigator directly on the Environments tab
navigate_to_tab "environments"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Agent should now:"
echo "1. Select 'base (root)' environment (if not already selected)"
echo "2. Click 'Channels' button and add 'conda-forge'"
echo "3. Search for 'seaborn' in available packages"
echo "4. Install seaborn and verify it appears in installed list"
