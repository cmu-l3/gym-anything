#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Add Contact Task ==="

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

echo "=== Add Contact Task Setup Complete ==="
echo "📇 Instructions:"
echo "  1. Open the Address Book (Tools > Address Book or Ctrl+Shift+B)"
echo "  2. Click 'New Contact' button or press Ctrl+N"
echo "  3. Enter Display Name: John Doe"
echo "  4. Enter Email: john.doe@example.com"
echo "  5. Click 'OK' or Save to add the contact"
