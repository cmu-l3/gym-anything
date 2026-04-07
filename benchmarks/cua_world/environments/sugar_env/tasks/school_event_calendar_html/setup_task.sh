#!/bin/bash
echo "=== Setting up school_event_calendar_html task ==="

# Record task start timestamp for mtime validation
date +%s > /tmp/calendar_task_start_ts
chmod 666 /tmp/calendar_task_start_ts

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to ensure agent creates them fresh
rm -f /home/ga/Documents/generate_calendar.py 2>/dev/null || true
rm -f /home/ga/Documents/school_calendar.html 2>/dev/null || true

# Close any open activity first to return to home view
su - ga -c "DISPLAY=:1 xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity
echo "Launching Terminal activity..."
su - ga -c "DISPLAY=:1 sugar-launch org.laptop.Terminal" &
sleep 10

# Verify Terminal is running
if pgrep -f "Terminal" > /dev/null 2>&1; then
    echo "Terminal activity is running"
else
    echo "WARNING: Terminal activity may not have started"
fi

# Take a verification screenshot
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png" 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== school_event_calendar_html task setup complete ==="
echo "Terminal is open."
echo "Agent must write generate_calendar.py and produce school_calendar.html in /home/ga/Documents/"