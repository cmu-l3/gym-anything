#!/bin/bash
set -e

echo "=== Setting up Standardize Workspace and Remediate Code Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create workspace and directories
WORKSPACE_DIR="/home/ga/workspace/starlette_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR/starlette"

# 1. Create starlette/applications.py with bad formatting
cat > "$WORKSPACE_DIR/starlette/applications.py" << 'EOF'
import typing

class Starlette:
  def __init__(self, debug: bool = False):
     self.debug=debug
       self.routes =[]

  def add_route( self, path: str, route: typing.Callable ):
     self.routes.append(( path,route))
EOF
chown -R ga:ga "$WORKSPACE_DIR/starlette/applications.py"

# 2. Create starlette/routing.py with linter errors
cat > "$WORKSPACE_DIR/starlette/routing.py" << 'EOF'
import typing
import sys
import os

class Route:
    def __init__(self, path: str, endpoint: typing.Callable):
        self.path = path
        self.endpoint = endpoint
        print(undefined_debug_var)
EOF
chown -R ga:ga "$WORKSPACE_DIR/starlette/routing.py"

# Ensure pip packages are available
pip3 install --no-cache-dir black flake8 pytest uvicorn > /dev/null 2>&1 || true

# Kill any existing VS Code instances
pkill -f "code" 2>/dev/null || true
sleep 2

# Launch VS Code in the workspace
echo "Launching VS Code..."
sudo -u ga DISPLAY=:1 code --new-window "$WORKSPACE_DIR" > /tmp/vscode_launch.log 2>&1 &
sleep 5

# Wait for VS Code window and maximize
wait_for_window "Visual Studio Code" 30
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss any welcome dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="