#!/bin/bash
set -e
echo "=== Setting up update_school_info task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database Services are running
echo "Checking database services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
sleep 2

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 3. Ensure Web Server is running
systemctl start apache2 2>/dev/null
sleep 2

# 4. Reset School Data to Known Initial State
# This ensures the agent isn't starting with the work already done
echo "Resetting school data..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "
    UPDATE schools 
    SET address='123 Main St', 
        city='City', 
        state='ST', 
        zipcode='12345', 
        phone='555-1234'
    WHERE id=1;
" 2>/dev/null

# Record initial state for verification reference
mysql -u opensis_user -p'opensis_password_123' opensis -N -B -e \
    "SELECT address, city, state, zipcode, phone FROM schools WHERE id=1" \
    2>/dev/null > /tmp/initial_school_data.txt

# 5. Launch Browser
# Kill any existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

echo "Starting Chrome..."
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Launch Chrome to login page
nohup sudo -u ga DISPLAY=:1 $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --window-size=1920,1080 \
    --disable-infobars \
    --password-store=basic \
    "http://localhost/opensis/" > /dev/null 2>&1 &

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || DISPLAY=:1 wmctrl -a "Chromium" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="