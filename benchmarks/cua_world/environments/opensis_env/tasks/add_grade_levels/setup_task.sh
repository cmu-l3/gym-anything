#!/bin/bash
set -e
echo "=== Setting up task: add_grade_levels ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database Services are running
echo "Checking database status..."
if ! systemctl is-active --quiet mariadb; then
    sudo systemctl start mariadb
    sleep 3
fi

# 3. Establish Clean State (Remove Grade 7/8 if they exist)
echo "Cleaning up any existing Grade 7/8 records..."
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "DELETE FROM school_gradelevels WHERE school_id = 1 AND short_name IN ('7', '8', '07', '08');" 2>/dev/null || true

# 4. Record Initial State
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT COUNT(*) FROM school_gradelevels WHERE school_id = 1;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_gl_count.txt
echo "Initial grade level count: $INITIAL_COUNT"

# 5. Ensure Browser is Running and Ready
# Kill any existing instances to ensure fresh login page
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

echo "Launching Chrome..."
# Determine correct chrome command
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Launch browser as 'ga' user
su - ga -c "DISPLAY=:1 $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --start-maximized \
    'http://localhost/opensis/' > /dev/null 2>&1 &"

# Wait for window to appear
echo "Waiting for browser window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || DISPLAY=:1 wmctrl -a "Chromium" 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="