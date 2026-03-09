#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Consolidate Experiments Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_middleware"
TASK_ASSETS="/workspace/tasks/consolidate_experiments/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Initialize git repo
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"

# Copy all experimental files from assets
echo "Copying experimental files..."
sudo -u ga cp "$TASK_ASSETS/rate_limiter_v1.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/rate_limiter_v2.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/rate_limiter_v3.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/test_rate_limiter_temp.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/debug_utils.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/benchmark_results.txt" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/requirements.txt" "$WORKSPACE_DIR/"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create initial commit with all experiments
cd "$WORKSPACE_DIR"
sudo -u ga git add .
sudo -u ga git commit -m "WIP: Experimenting with rate limiter approaches" || true

# Open VSCode to the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Consolidate Experiments Task Setup Complete ==="
echo "📝 Workspace: $WORKSPACE_DIR"
echo "📝 Instructions:"
echo "  1. Rename rate_limiter_v3.py to rate_limiter.py"
echo "  2. Delete experimental files: v1, v2, v3 (original), test_temp, debug_utils, benchmark"
echo "  3. Clean rate_limiter.py: remove debug prints, TODOs, commented code"
echo "  4. Add documentation: module, class, and method docstrings"
echo "  5. Update requirements.txt with redis>=4.5.0"
echo "  6. Git commit with message: 'Add Redis-based rate limiter'"