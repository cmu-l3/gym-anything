#!/bin/bash
echo "=== Setting up enable_https_socioboard task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure Apache is running and HTTP is working
systemctl start apache2 2>/dev/null || true

# Wait for Socioboard to be ready on HTTP (it might be starting up in the background)
echo "Waiting for Socioboard HTTP interface..."
for i in {1..30}; do
    if curl -s http://localhost/ > /dev/null; then
        echo "Socioboard HTTP interface ready."
        break
    fi
    sleep 2
done

# Force a clean starting state: Disable SSL module and SSL sites if they were somehow enabled
echo "Ensuring plain HTTP starting state..."
a2dismod ssl 2>/dev/null || true
a2dissite default-ssl 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true

# Reset .env file APP_URL to http://localhost
ENV_FILE="/opt/socioboard/socioboard-web-php/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Resetting APP_URL in .env to http..."
    sed -i 's|^APP_URL=.*|APP_URL=http://localhost|' "$ENV_FILE"
fi

# Make sure Firefox is running and focused on the HTTP dashboard
echo "Launching Firefox..."
if command -v navigate_to >/dev/null 2>&1; then
    navigate_to "http://localhost/"
else
    su - ga -c "DISPLAY=:1 firefox http://localhost/ > /dev/null 2>&1 &"
    sleep 5
    DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take an initial screenshot
echo "Capturing initial screenshot..."
sleep 2
DISPLAY=:1 scrot /tmp/task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="