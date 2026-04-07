#!/bin/bash
set -e
echo "=== Setting up configure_grade_scale task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database and Web Server are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 3

# 3. Clean State: Remove the specific grade scale if it already exists
# This ensures the agent must actually create it
echo "Cleaning up any existing 'Standard 4.0 Scale'..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "
    DELETE rg FROM report_card_grades rg
    INNER JOIN report_card_grade_scales rgs ON rg.grade_scale_id = rgs.id
    WHERE rgs.title = 'Standard 4.0 Scale';
    DELETE FROM report_card_grade_scales WHERE title = 'Standard 4.0 Scale';
" 2>/dev/null || true

# 4. Record initial counts for anti-gaming verification
INITIAL_SCALES=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM report_card_grade_scales" 2>/dev/null || echo "0")
echo "$INITIAL_SCALES" > /tmp/initial_scale_count.txt

INITIAL_GRADES=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM report_card_grades" 2>/dev/null || echo "0")
echo "$INITIAL_GRADES" > /tmp/initial_grade_count.txt

# 5. Launch Chrome and prepare window
# Kill existing instances to start fresh
pkill -f chrome 2>/dev/null || true
sleep 1

# Launch Chrome pointing to OpenSIS
echo "Launching Chrome..."
su - ga -c 'DISPLAY=:1 google-chrome-stable \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --start-maximized \
    "http://localhost/opensis/" &'

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "chrome|opensis"; then
        echo "Chrome window detected"
        break
    fi
    sleep 1
done

# Ensure maximized and focused
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# 6. Capture initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="