#!/bin/bash
echo "=== Setting up write_alice_passage task ==="

# Ensure the Alice in Wonderland text file is available
if [ ! -f /home/ga/Documents/alice_in_wonderland.txt ]; then
    echo "WARNING: Alice text not found, copying from assets..."
    cp /workspace/data/alice_in_wonderland_excerpt.txt /home/ga/Documents/alice_in_wonderland.txt 2>/dev/null || true
fi

# Sugar runs as the GDM session on :1.
# sugar-launch requires the user's DBUS session bus.
SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Close any open activity first to return to home view.
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Write activity programmatically via DBUS
echo "Launching Write activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.AbiWordActivity" &
sleep 10

# Verify Write activity is running
if pgrep -f "AbiWord" > /dev/null 2>&1; then
    echo "Write activity is running"
else
    echo "WARNING: Write activity may not have started"
fi

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_start_state.png" 2>/dev/null || true

echo "=== write_alice_passage task setup complete ==="
echo "Write activity should be open with a blank document"
echo "Agent should type the Alice passage and set the document title"
