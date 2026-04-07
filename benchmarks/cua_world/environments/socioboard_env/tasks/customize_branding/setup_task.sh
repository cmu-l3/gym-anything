#!/bin/bash
echo "=== Setting up customize_branding task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record precise task start time for anti-gaming checks (find -newer)
date +%s > /tmp/task_start_time.txt

# Wait for Socioboard frontend to be ready
if ! wait_for_http "http://localhost/" 120; then
    echo "WARNING: Socioboard not reachable at http://localhost/ immediately. Continuing..."
fi

# Pre-clear Laravel view cache to ensure baseline is fresh
su - ga -c "cd /opt/socioboard/socioboard-web-php && php artisan view:clear" 2>/dev/null || true

# Open Socioboard login page in Firefox
open_socioboard_page "http://localhost/login"

# Take initial screenshot of unbranded state
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="