#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Compose Email Task ==="

# Wait for Thunderbird to be ready
if ! wait_for_thunderbird_ready 30; then
    echo "ERROR: Thunderbird not ready"
    # Continue anyway - may already be running from setup
fi

# Click center of desktop to focus it (important pattern from other envs)
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

# Ensure we're on the main Thunderbird window (not compose window)
# Close any existing compose windows
su - ga -c "DISPLAY=:1 wmctrl -c 'Write:' 2>/dev/null" || true
sleep 0.3

echo "=== Compose Email Task Setup Complete ==="
echo "📧 Instructions:"
echo "  1. Click 'Write' button or press Ctrl+N to compose new email"
echo "  2. Enter recipient: recipient@example.com"
echo "  3. Enter subject: Meeting Tomorrow"
echo "  4. Write email body containing the word 'agenda'"
echo "  5. Send email with Ctrl+Return or click Send button"
