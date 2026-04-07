#!/bin/bash
set -e
echo "=== Setting up lock_marking_period task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Ensure OpenSIS is running
if ! systemctl is-active --quiet mariadb; then
    sudo systemctl start mariadb
    sleep 3
fi
if ! systemctl is-active --quiet apache2; then
    sudo systemctl start apache2
fi

# 2. Prepare Database State
# We need to ensure 'Quarter 1' exists and is OPEN (Y/Y), and 'Full Year' exists and is OPEN (Y/Y)
echo "Configuring database state..."

# SQL to setup marking periods
# Note: School ID is assumed to be 1 based on env setup
# We use ON DUPLICATE KEY UPDATE to reset state if it exists
sudo mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Ensure Full Year exists and is OPEN
INSERT INTO school_years (marking_period_id, syear, school_id, title, short_name, sort_order, start_date, end_date, does_grades, does_comments)
VALUES (1, 2025, 1, 'Full Year', 'FY', 1, '2024-08-01', '2025-06-30', 'Y', 'Y')
ON DUPLICATE KEY UPDATE does_grades='Y', does_comments='Y';

-- Ensure Quarter 1 exists and is OPEN (this is what the agent must change)
-- We'll use ID 2 for Q1
INSERT INTO school_years (marking_period_id, syear, school_id, title, short_name, sort_order, start_date, end_date, does_grades, does_comments)
VALUES (2, 2025, 1, 'Quarter 1', 'Q1', 2, '2024-08-01', '2024-10-31', 'Y', 'Y')
ON DUPLICATE KEY UPDATE does_grades='Y', does_comments='Y', title='Quarter 1';
EOF

# Record initial state for verification
INITIAL_STATE=$(sudo mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT marking_period_id, title, does_grades, does_comments FROM school_years WHERE school_id=1")
echo "$INITIAL_STATE" > /tmp/initial_db_state.txt
echo "Initial DB State:"
echo "$INITIAL_STATE"

# 3. Setup Browser
echo "Launching Chrome..."
# Kill existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Determine browser command
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="google-chrome"
fi

# Launch browser to login page
nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --start-maximized \
    "http://localhost/opensis/" > /tmp/chrome_launch.log 2>&1 &

# Wait for window
echo "Waiting for browser..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium\|OpenSIS"; then
        echo "Browser detected."
        break
    fi
    sleep 1
done

# Ensure maximized and focused
DISPLAY=:1 wmctrl -a "OpenSIS" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="