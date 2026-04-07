#!/bin/bash
echo "=== Setting up implement_compliance_login_banner task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming modification checks
date +%s > /tmp/task_start_time.txt

# Clear view cache to ensure we start from a clean state
if [ -d "/opt/socioboard/socioboard-web-php" ]; then
    su - ga -c "cd /opt/socioboard/socioboard-web-php && php artisan view:clear" >/dev/null 2>&1 || true
fi

# Ensure Firefox is running and navigated to the login page
log "Starting Firefox at http://localhost/login..."
ensure_firefox_running "http://localhost/login"
sleep 5

# Ensure ga has full ownership of the directory to allow editing
chown -R ga:ga /opt/socioboard/socioboard-web-php 2>/dev/null || true

# Maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="