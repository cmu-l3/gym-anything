#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Password Export to CSV Task Setup ==="
echo "Task: Export saved passwords from Chrome Password Manager to CSV file"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python packages for password database manipulation
pip3 install -q pycryptodome 2>/dev/null || pip3 install -q pycrypto 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create sample passwords in Chrome's Login Data database
echo "Setting up sample passwords in Chrome password manager..."
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"

# If Chrome is running, stop it temporarily to modify the database
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Stopping Chrome to add sample passwords..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Create Login Data database with sample passwords
# Note: Chrome's real passwords are encrypted, but for testing we can add unencrypted entries
# The export functionality will still work and create a valid CSV structure
LOGIN_DB="${CHROME_PROFILE}/Login Data"

# Initialize or backup existing database
if [ -f "$LOGIN_DB" ]; then
    echo "Backing up existing Login Data..."
    cp "$LOGIN_DB" "${LOGIN_DB}.backup_$(date +%s)"
fi

# Create/update Login Data with sample passwords
python3 <<'PYTHON_SCRIPT'
import sqlite3
import os
from datetime import datetime

# Chrome profile path
profile_path = "/home/ga/.config/google-chrome-cdp/Default"
login_db_path = os.path.join(profile_path, "Login Data")

# Ensure directory exists
os.makedirs(profile_path, exist_ok=True)

# Create or connect to database
conn = sqlite3.connect(login_db_path)
cursor = conn.cursor()

# Create logins table if it doesn't exist (Chrome's schema)
cursor.execute('''
    CREATE TABLE IF NOT EXISTS logins (
        origin_url TEXT NOT NULL,
        action_url TEXT,
        username_element TEXT,
        username_value TEXT,
        password_element TEXT,
        password_value BLOB,
        submit_element TEXT,
        signon_realm TEXT NOT NULL,
        date_created INTEGER NOT NULL,
        blacklisted_by_user INTEGER NOT NULL,
        scheme INTEGER NOT NULL,
        password_type INTEGER,
        times_used INTEGER,
        form_data BLOB,
        display_name TEXT,
        icon_url TEXT,
        federation_url TEXT,
        skip_zero_click INTEGER,
        generation_upload_status INTEGER,
        possible_username_pairs BLOB,
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date_last_used INTEGER,
        moving_blocked_for BLOB,
        date_password_modified INTEGER
    )
''')

# Sample password entries for testing
# Note: password_value would normally be encrypted, but for export testing
# we can use simple entries that Chrome will still export
sample_passwords = [
    {
        'origin_url': 'https://example.com/',
        'action_url': 'https://example.com/login',
        'username_value': 'testuser1@example.com',
        'password_value': b'Password123!',  # Simplified for testing
        'signon_realm': 'https://example.com/',
        'date_created': int(datetime.now().timestamp() * 1000000),
    },
    {
        'origin_url': 'https://github.com/',
        'action_url': 'https://github.com/session',
        'username_value': 'testuser2',
        'password_value': b'SecurePass456!',
        'signon_realm': 'https://github.com/',
        'date_created': int(datetime.now().timestamp() * 1000000),
    },
    {
        'origin_url': 'https://mail.google.com/',
        'action_url': 'https://accounts.google.com/signin',
        'username_value': 'testuser3@gmail.com',
        'password_value': b'GooglePass789!',
        'signon_realm': 'https://accounts.google.com/',
        'date_created': int(datetime.now().timestamp() * 1000000),
    }
]

# Insert sample passwords
for pwd in sample_passwords:
    try:
        cursor.execute('''
            INSERT INTO logins (
                origin_url, action_url, username_value, password_value,
                signon_realm, date_created, blacklisted_by_user, scheme,
                times_used, date_last_used, date_password_modified
            ) VALUES (?, ?, ?, ?, ?, ?, 0, 0, 0, ?, ?)
        ''', (
            pwd['origin_url'],
            pwd['action_url'],
            pwd['username_value'],
            pwd['password_value'],
            pwd['signon_realm'],
            pwd['date_created'],
            pwd['date_created'],
            pwd['date_created']
        ))
    except sqlite3.IntegrityError:
        # Entry might already exist
        pass

conn.commit()
conn.close()

print("✓ Sample passwords added to Chrome password manager")
print(f"  - example.com: testuser1@example.com")
print(f"  - github.com: testuser2")
print(f"  - mail.google.com: testuser3@gmail.com")
PYTHON_SCRIPT

# Set proper ownership
chown -R ga:ga "$CHROME_PROFILE"

# Now start Chrome
echo "Starting Chrome..."

if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Launching Chrome..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 3

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to starting URL
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify passwords were added
PASSWORD_COUNT=$(sqlite3 "$LOGIN_DB" "SELECT COUNT(*) FROM logins;" 2>/dev/null || echo "0")
echo "✓ Chrome password manager contains $PASSWORD_COUNT saved password(s)"

# Clear Downloads folder to ensure clean state
DOWNLOADS_DIR="/home/ga/Downloads"
mkdir -p "$DOWNLOADS_DIR"
rm -f "$DOWNLOADS_DIR"/*.csv 2>/dev/null || true
echo "✓ Downloads folder cleared for clean export"

echo "=== Setup complete ==="
echo "Chrome is ready with sample passwords in password manager"
echo ""
echo "Agent should now:"
echo "  1. Navigate to chrome://settings/passwords or chrome://password-manager"
echo "  2. Click the three-dot menu (⋮) in Password Manager"
echo "  3. Click 'Export passwords' or 'Download passwords'"
echo "  4. Confirm the export in the security dialog"
echo "  5. Save the file as 'chrome_passwords_export.csv' in Downloads folder"