#!/bin/bash
echo "=== Setting up Configure Apache API Proxy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (checking if .env was modified AFTER start)
date +%s > /tmp/task_start_time.txt

# Reset the .env file to local ports to ensure a clean slate
ENV_FILE="/opt/socioboard/socioboard-web-php/.env"
if [ -f "$ENV_FILE" ]; then
    echo "Resetting $ENV_FILE to explicit local ports..."
    sed -i 's|^API_URL=.*|API_URL=http://localhost:3000|' "$ENV_FILE"
    sed -i 's|^API_URL_FEEDS=.*|API_URL_FEEDS=http://localhost:3001|' "$ENV_FILE"
    sed -i 's|^API_URL_PUBLISH=.*|API_URL_PUBLISH=http://localhost:3002|' "$ENV_FILE"
    sed -i 's|^API_URL_NOTIFICATION=.*|API_URL_NOTIFICATION=http://localhost:3003|' "$ENV_FILE"
fi

# Ensure proxy modules are DISABLED to make the agent enable them
echo "Disabling Apache proxy modules..."
a2dismod -f proxy proxy_http 2>/dev/null || true

# Strip any existing proxy configs from default host to avoid false positives
APACHE_CONF="/etc/apache2/sites-available/000-default.conf"
if [ -f "$APACHE_CONF" ]; then
    echo "Cleaning up $APACHE_CONF..."
    sed -i '/ProxyPass /d' "$APACHE_CONF"
    sed -i '/ProxyPassReverse /d' "$APACHE_CONF"
fi

# Restart Apache to apply clean state
systemctl restart apache2

# Ensure pm2 microservices are running
sudo -u root pm2 start all 2>/dev/null || true

# Open a terminal for the agent to start working
echo "Launching terminal..."
if ! pgrep -f gnome-terminal > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/opt/socioboard/socioboard-web-php &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for stabilization
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="