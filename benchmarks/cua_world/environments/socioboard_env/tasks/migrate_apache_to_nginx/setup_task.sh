#!/bin/bash
echo "=== Setting up migrate_apache_to_nginx task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Apache2 is currently running and active on port 80
echo "Ensuring Apache2 is the active web server..."
systemctl unmask apache2 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Make sure Nginx is stopped and out of the way initially
systemctl stop nginx 2>/dev/null || true

# Wait for Socioboard frontend to be reachable
echo "Waiting for Socioboard to be reachable on Apache..."
for i in {1..30}; do
    if curl -s http://localhost/ | grep -qi "socioboard"; then
        echo "Socioboard is reachable."
        break
    fi
    sleep 2
done

# Launch a terminal for the user to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting terminal for the agent..."
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 3
fi

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state (for evidence)
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="