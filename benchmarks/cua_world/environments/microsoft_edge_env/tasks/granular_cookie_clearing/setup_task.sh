#!/bin/bash
set -e
echo "=== Setting up Granular Cookie Clearing Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure we have a clean slate mostly, but keep preferences
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2

# Profile location
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"
# New Chromium versions use Network/Cookies, older use Cookies
if [ -d "$PROFILE_DIR/Network" ]; then
    COOKIES_DB="$PROFILE_DIR/Network/Cookies"
else
    COOKIES_DB="$PROFILE_DIR/Cookies"
fi

echo "Detected Cookies DB location: $COOKIES_DB"

# 1. Populate Cookies
# We launch Edge pointing to these sites to generate real cookies
# We use nohup and backgrounding to let them load
echo "Populating cookies..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --restore-last-session \
    --no-default-browser-check \
    'https://github.com' \
    'https://stackoverflow.com' \
    'https://www.google.com' \
    > /dev/null 2>&1 &"

EDGE_PID=$!

# Wait for sites to load and write cookies (30s should be enough for basic session cookies)
echo "Waiting for sites to load (30s)..."
sleep 30

# 2. Kill Edge to flush cookies to SQLite DB
echo "Closing Edge to flush DB..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 5

# 3. Verify Initial State (Internal Check)
if [ -f "$COOKIES_DB" ]; then
    # Create temp copy to read
    cp "$COOKIES_DB" /tmp/cookies_check.sqlite
    
    GH_COUNT=$(sqlite3 /tmp/cookies_check.sqlite "SELECT count(*) FROM cookies WHERE host_key LIKE '%github.com%';" 2>/dev/null || echo "0")
    SO_COUNT=$(sqlite3 /tmp/cookies_check.sqlite "SELECT count(*) FROM cookies WHERE host_key LIKE '%stackoverflow.com%';" 2>/dev/null || echo "0")
    GO_COUNT=$(sqlite3 /tmp/cookies_check.sqlite "SELECT count(*) FROM cookies WHERE host_key LIKE '%google.com%';" 2>/dev/null || echo "0")
    
    echo "Initial Cookie Counts - GitHub: $GH_COUNT, StackOverflow: $SO_COUNT, Google: $GO_COUNT"
    
    # Check if we failed to populate (network issues, etc)
    if [ "$GH_COUNT" -eq 0 ] || [ "$SO_COUNT" -eq 0 ] || [ "$GO_COUNT" -eq 0 ]; then
        echo "WARNING: Cookie population might have failed. Attempting manual insert fallback..."
        # Fallback: manually inject valid-looking cookies if network failed
        # This ensures the task is solvable even without internet
        sqlite3 "$COOKIES_DB" <<EOF
INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, encrypted_value, samesite, source_scheme, source_port, is_same_party) 
VALUES (13300000000000000, '.github.com', 'user_session', 'fake_session_data', '/', 0, 1, 1, 13300000000000000, 0, 0, 1, '', 0, 2, 443, 0);
INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, encrypted_value, samesite, source_scheme, source_port, is_same_party) 
VALUES (13300000000000000, '.stackoverflow.com', 'prov', 'fake_prov_data', '/', 0, 1, 1, 13300000000000000, 0, 0, 1, '', 0, 2, 443, 0);
INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, encrypted_value, samesite, source_scheme, source_port, is_same_party) 
VALUES (13300000000000000, '.google.com', 'NID', 'fake_nid_data', '/', 0, 1, 1, 13300000000000000, 0, 0, 1, '', 0, 2, 443, 0);
EOF
    fi
    rm -f /tmp/cookies_check.sqlite
else
    echo "ERROR: Cookies DB not found at $COOKIES_DB"
fi

# 4. Re-launch Edge for the agent (Clean tab)
echo "Launching Edge for agent..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    'about:blank' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge window confirmed."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="