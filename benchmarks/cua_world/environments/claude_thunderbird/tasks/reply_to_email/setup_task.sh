#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Reply to Email Task ==="

# Wait for Thunderbird to be ready
if ! wait_for_thunderbird_ready 30; then
    echo "ERROR: Thunderbird not ready"
fi

# Click center of desktop to focus it
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Thunderbird window
echo "Focusing Thunderbird window..."
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Ensure Inbox is selected to show the test email
# Navigate to Inbox folder
su - ga -c "DISPLAY=:1 wmctrl -a Thunderbird" || true
sleep 0.3

echo "=== Reply to Email Task Setup Complete ==="
echo "📧 Instructions:"
echo "  1. Find the email from 'sender@example.com' with subject 'Welcome to Thunderbird'"
echo "  2. Click on the email to select it"
echo "  3. Click 'Reply' button or press Ctrl+R"
echo "  4. Write your reply containing the word 'thanks'"
echo "  5. Send the reply with Ctrl+Return or click Send button"
