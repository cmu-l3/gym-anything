#!/bin/bash
set -e
echo "=== Setting up task: add_discipline_offense_code ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Start Services
echo "Starting services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 2. Clean State (Remove 'Cyberbullying' if it exists)
echo "Cleaning database state..."
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "DELETE FROM discipline_field_usage WHERE title LIKE '%Cyberbullying%';" 2>/dev/null || true

# 3. Record Initial State for Anti-Gaming
# We record the maximum ID in the discipline table to ensure the new record is created *after* this point
INITIAL_MAX_ID=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT COALESCE(MAX(id), 0) FROM discipline_field_usage;" 2>/dev/null || echo "0")
echo "$INITIAL_MAX_ID" > /tmp/initial_max_id.txt
echo "Initial Max ID: $INITIAL_MAX_ID"

# Record start time
date +%s > /tmp/task_start_time.txt

# 4. Launch Browser
# Kill existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

echo "Launching browser..."
OPENSIS_URL="http://localhost/opensis/"

if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    BROWSER="chromium-browser"
else
    BROWSER="chrome-browser"
fi

# Launch in background as 'ga' user
su - ga -c "DISPLAY=:1 $BROWSER --no-sandbox --start-maximized '$OPENSIS_URL' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || DISPLAY=:1 wmctrl -a "Chromium" 2>/dev/null || true

# 5. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="