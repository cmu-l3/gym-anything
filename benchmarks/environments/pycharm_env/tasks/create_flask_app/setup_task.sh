#!/bin/bash
echo "=== Setting up create_flask_app task ==="

# Ensure PyCharm is running
source /workspace/scripts/task_utils.sh

# CRITICAL: Clean up any pre-existing solution files
# This runs AFTER checkpoint restore to ensure clean state
echo "Cleaning pre-existing solution files..."

# Remove hello_flask directory completely
rm -rf /home/ga/PycharmProjects/hello_flask 2>/dev/null || true
sync

# Verify cleanup was successful
sleep 2
if [ -d "/home/ga/PycharmProjects/hello_flask" ]; then
    echo "ERROR: Failed to clean up hello_flask directory, retrying with force..."
    rm -rf /home/ga/PycharmProjects/hello_flask
    sync
    sleep 1
fi

# Final verification - MUST NOT EXIST
if [ -d "/home/ga/PycharmProjects/hello_flask" ]; then
    echo "CRITICAL ERROR: hello_flask directory still exists after cleanup!"
    echo "Contents:"
    ls -la /home/ga/PycharmProjects/hello_flask/
    echo "ABORTING - Pre-baked solution detected in checkpoint!"
    exit 1
fi

# Verify no hello_flask files anywhere in PycharmProjects
if find /home/ga/PycharmProjects -name "hello_flask*" 2>/dev/null | grep -q .; then
    echo "WARNING: Found hello_flask remnants, cleaning..."
    find /home/ga/PycharmProjects -name "hello_flask*" -exec rm -rf {} \; 2>/dev/null || true
fi

echo "Cleanup verified: hello_flask directory does not exist"
echo "PycharmProjects contents:"
ls -la /home/ga/PycharmProjects/ 2>/dev/null || echo "(empty)"

# Also clean any exported results from previous runs
rm -f /tmp/task_result.json 2>/dev/null || true

# Record start time for timestamp validation
echo "$(date +%s)" > /tmp/episode_start_time
echo "Episode start time recorded: $(cat /tmp/episode_start_time)"

# Wait for PyCharm to be ready (Welcome screen or project window)
wait_for_pycharm 60 || echo "WARNING: PyCharm not detected"

# Dismiss any dialogs that might appear
dismiss_dialogs 3

# Focus and maximize PyCharm window
focus_pycharm_window

# Additional stabilization wait
sleep 3

# Take initial screenshot showing clean state
take_screenshot /tmp/task_start.png

# Verify the screenshot shows PyCharm Welcome (no project open)
echo "Initial screenshot saved to /tmp/task_start.png"

echo "=== Task setup complete ==="
echo "Agent should now create hello_flask project from scratch using PyCharm GUI"
