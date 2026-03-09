#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Calendar Event Task ==="

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

echo "=== Create Calendar Event Task Setup Complete ==="
echo "📅 Instructions:"
echo "  1. Switch to Calendar view (click Calendar tab or press Ctrl+Shift+C)"
echo "  2. Create a new event (click 'New Event' or press Ctrl+I)"
echo "  3. Enter title: Team Meeting"
echo "  4. Set date to tomorrow"
echo "  5. Set time to 2:00 PM (14:00)"
echo "  6. Save the event"
