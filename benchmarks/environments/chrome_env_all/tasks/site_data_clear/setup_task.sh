#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Complete Site Data Deletion Task Setup: site_data_clear@1 ==="
echo "Task: Remove all stored data for example.org domain"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 bc || true

# Install Python libraries for data injection
pip3 install -q pycryptodome 2>/dev/null || pip3 install -q pycrypto 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Define target domain for the task
TARGET_DOMAIN="example.org"
echo "Target domain for data deletion: $TARGET_DOMAIN"

# Ensure Chrome is running first
echo "Checking Chrome status..."
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 3

# Get Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
if [ ! -d "$CHROME_PROFILE" ]; then
    # Try alternative location
    CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
fi

echo "Using Chrome profile: $CHROME_PROFILE"

# Close Chrome temporarily to inject test data
echo "Stopping Chrome to inject test data..."
pkill -f "google-chrome" || true
sleep 2

# Ensure Chrome is fully stopped
pkill -9 -f "google-chrome" || true
sleep 1

# ===== INJECT TEST DATA FOR example.org =====

# 1. Inject cookies into Cookies database
echo "Injecting test cookies for $TARGET_DOMAIN..."
COOKIES_DB="$CHROME_PROFILE/Cookies"

if [ -f "$COOKIES_DB" ]; then
    # Backup original
    cp "$COOKIES_DB" "$COOKIES_DB.backup" || true
    
    # Calculate expiry time (1 year from now in microseconds since 1601-01-01)
    CURRENT_TIME=$(date +%s)
    EXPIRY_TIME=$((CURRENT_TIME + 31536000))  # +1 year
    # Chrome uses microseconds since Windows epoch (1601-01-01)
    # Unix epoch is 1970-01-01, so we need to add the difference
    CHROME_EXPIRY=$(echo "($EXPIRY_TIME + 11644473600) * 1000000" | bc)
    CHROME_CREATION=$(echo "($(date +%s) + 11644473600) * 1000000" | bc)
    
    # Insert test cookies
    sqlite3 "$COOKIES_DB" <<EOF
INSERT INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party)
VALUES 
($CHROME_CREATION, '.example.org', 'https://example.org', 'session_id', 'abc123xyz', '/', $CHROME_EXPIRY, 1, 0, $CHROME_CREATION, 1, 1, 1, 0, 2, 443, 0),
($CHROME_CREATION, '.example.org', 'https://example.org', 'user_pref', 'dark_mode', '/', $CHROME_EXPIRY, 0, 0, $CHROME_CREATION, 1, 1, 1, 0, 2, 443, 0),
($CHROME_CREATION, 'example.org', 'https://example.org', 'tracking_id', 'track_xyz789', '/', $CHROME_EXPIRY, 1, 1, $CHROME_CREATION, 1, 1, 1, 0, 2, 443, 0);
EOF
    
    echo "✓ Injected 3 test cookies for $TARGET_DOMAIN"
else
    echo "⚠ Warning: Cookies database not found, creating minimal version"
    # Chrome might not have created cookies file yet, create schema
    sqlite3 "$COOKIES_DB" <<EOF
CREATE TABLE cookies(
    creation_utc INTEGER NOT NULL,
    host_key TEXT NOT NULL,
    top_frame_site_key TEXT NOT NULL,
    name TEXT NOT NULL,
    value TEXT NOT NULL,
    encrypted_value BLOB DEFAULT '',
    path TEXT NOT NULL,
    expires_utc INTEGER NOT NULL,
    is_secure INTEGER NOT NULL,
    is_httponly INTEGER NOT NULL,
    last_access_utc INTEGER NOT NULL,
    has_expires INTEGER NOT NULL DEFAULT 1,
    is_persistent INTEGER NOT NULL DEFAULT 1,
    priority INTEGER NOT NULL DEFAULT 1,
    samesite INTEGER NOT NULL DEFAULT -1,
    source_scheme INTEGER NOT NULL DEFAULT 0,
    source_port INTEGER NOT NULL DEFAULT -1,
    is_same_party INTEGER NOT NULL DEFAULT 0,
    UNIQUE (host_key, name, path)
);
EOF
    # Then insert cookies using same logic as above
    CURRENT_TIME=$(date +%s)
    EXPIRY_TIME=$((CURRENT_TIME + 31536000))
    CHROME_EXPIRY=$(echo "($EXPIRY_TIME + 11644473600) * 1000000" | bc)
    CHROME_CREATION=$(echo "($(date +%s) + 11644473600) * 1000000" | bc)
    
    sqlite3 "$COOKIES_DB" <<EOF
INSERT INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party)
VALUES 
($CHROME_CREATION, '.example.org', 'https://example.org', 'session_id', 'abc123xyz', '/', $CHROME_EXPIRY, 1, 0, $CHROME_CREATION, 1, 1, 1, 0, 2, 443, 0);
EOF
    echo "✓ Created Cookies database with test data"
fi

# Set proper ownership
chown ga:ga "$COOKIES_DB" || true

# 2. Inject permissions into Preferences file
echo "Injecting test permissions for $TARGET_DOMAIN..."
PREFS_FILE="$CHROME_PROFILE/Preferences"

if [ -f "$PREFS_FILE" ]; then
    # Backup original
    cp "$PREFS_FILE" "$PREFS_FILE.backup" || true
    
    # Use Python to safely modify JSON
    python3 <<PYTHON_EOF
import json
import sys

prefs_file = "$PREFS_FILE"
domain = "$TARGET_DOMAIN"

try:
    with open(prefs_file, 'r', encoding='utf-8') as f:
        prefs = json.load(f)
    
    # Ensure structure exists
    if 'profile' not in prefs:
        prefs['profile'] = {}
    if 'content_settings' not in prefs['profile']:
        prefs['profile']['content_settings'] = {}
    if 'exceptions' not in prefs['profile']['content_settings']:
        prefs['profile']['content_settings']['exceptions'] = {}
    
    exceptions = prefs['profile']['content_settings']['exceptions']
    
    # Add notification permission
    if 'notifications' not in exceptions:
        exceptions['notifications'] = {}
    exceptions['notifications'][f'https://{domain}:443,*'] = {
        'last_modified': '13360000000000000',
        'setting': 1
    }
    
    # Add geolocation permission
    if 'geolocation' not in exceptions:
        exceptions['geolocation'] = {}
    exceptions['geolocation'][f'https://{domain}:443,*'] = {
        'last_modified': '13360000000000000',
        'setting': 1
    }
    
    # Add custom zoom level
    if 'partition' not in prefs:
        prefs['partition'] = {}
    if 'per_host_zoom_levels' not in prefs['partition']:
        prefs['partition']['per_host_zoom_levels'] = {}
    prefs['partition']['per_host_zoom_levels'][domain] = 1.25
    
    # Write back
    with open(prefs_file, 'w', encoding='utf-8') as f:
        json.dump(prefs, f, indent=2)
    
    print("✓ Injected permissions and zoom level for", domain)
    sys.exit(0)
    
except Exception as e:
    print(f"⚠ Warning: Could not modify Preferences: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
    
else
    echo "⚠ Warning: Preferences file not found at $PREFS_FILE"
fi

# Set proper ownership
chown ga:ga "$PREFS_FILE" || true

# 3. Create some local storage data (optional, simulated)
echo "Setting up local storage indicators..."
LOCAL_STORAGE_DIR="$CHROME_PROFILE/Local Storage/leveldb"
mkdir -p "$LOCAL_STORAGE_DIR" || true
chown -R ga:ga "$CHROME_PROFILE/Local Storage" 2>/dev/null || true

echo "✓ Test data injection complete"
echo "  - 3 cookies for $TARGET_DOMAIN"
echo "  - Notification permission granted"
echo "  - Geolocation permission granted"
echo "  - Custom zoom level set to 125%"

# ===== RESTART CHROME =====

echo "Restarting Chrome with injected data..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

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

# Navigate to starting page
echo "Navigating to starting page..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Verify cookies were injected
echo "Verifying injected data..."
COOKIE_COUNT=$(sqlite3 "$COOKIES_DB" "SELECT COUNT(*) FROM cookies WHERE host_key LIKE '%$TARGET_DOMAIN%';" 2>/dev/null || echo "0")
echo "✓ Found $COOKIE_COUNT cookie(s) for $TARGET_DOMAIN in database"

echo "=== Setup complete ==="
echo ""
echo "Chrome is ready with test data for: $TARGET_DOMAIN"
echo ""
echo "Agent should:"
echo "  1. Navigate to chrome://settings/content/all"
echo "     OR: Settings → Privacy and security → Third-party cookies → See all site data"
echo "  2. Search for 'example.org' in the site data list"
echo "  3. Click on example.org entry"
echo "  4. Click 'Remove' or 'Clear data' button"
echo "  5. Confirm deletion in the dialog"
echo ""
echo "The verifier will check that all data for $TARGET_DOMAIN is removed."