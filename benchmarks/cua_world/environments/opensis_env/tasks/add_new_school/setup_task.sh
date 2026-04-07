#!/bin/bash
set -e
echo "=== Setting up add_new_school task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database and Web Server are running
echo "Checking services..."
service mariadb start 2>/dev/null || systemctl start mariadb || true
service apache2 start 2>/dev/null || systemctl start apache2 || true
sleep 2

# 3. Clean up any previous attempts (Idempotency)
# We delete any school with 'Riverside' in the title to ensure a clean start
echo "Cleaning up previous records..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "DELETE FROM schools WHERE title LIKE '%Riverside%';" 2>/dev/null || true

# 4. Record Initial State (School IDs)
# We save the list of existing school IDs to verify the new one is actually new
echo "Recording initial state..."
INITIAL_IDS=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT GROUP_CONCAT(id) FROM schools;" 2>/dev/null || echo "")
echo "$INITIAL_IDS" > /tmp/initial_school_ids.txt
echo "Initial School IDs: $INITIAL_IDS"

# 5. setup Chrome
# Kill any existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Start Chrome on the Login Page
echo "Starting Browser..."
if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    BROWSER="chromium-browser"
else
    BROWSER="google-chrome" # Fallback
fi

# Launch browser as user 'ga'
su - ga -c "DISPLAY=:1 $BROWSER \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --window-size=1920,1080 \
    --password-store=basic \
    http://localhost/opensis/ &"

# 6. Wait for window and maximize
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "chrome|chromium|opensis"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Opensis" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="