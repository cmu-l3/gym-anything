#!/bin/bash
set -e
echo "=== Setting up create_circular_lifecycle_diagram task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/sdlc_lifecycle.eddx 2>/dev/null || true
rm -f /home/ga/Documents/sdlc_lifecycle.png 2>/dev/null || true
chown -R ga:ga /home/ga/Documents

# Record initial state of Documents directory
ls -la /home/ga/Documents/ > /tmp/initial_documents_state.txt 2>/dev/null || true

# Kill any existing EdrawMax instances for clean state
kill_edrawmax

# Launch EdrawMax fresh (no file argument = blank canvas / home screen)
# This usually opens the "New" page or a blank drawing depending on config
launch_edrawmax
wait_for_edrawmax 90

# Wait for the full UI to render
sleep 20

# Dismiss startup dialogs (Account Login, File Recovery, banners)
dismiss_edrawmax_dialogs

# Maximize the window
maximize_edrawmax

# If we are on the "Home/New" screen (common startup state), we want to leave it 
# either as is (letting agent click New) or prep a blank drawing.
# The task description implies starting from a blank canvas state is fine, 
# or the agent can create new. We'll leave it in the maximized startup state.

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "EdrawMax is open. Agent should create a circular SDLC lifecycle diagram."