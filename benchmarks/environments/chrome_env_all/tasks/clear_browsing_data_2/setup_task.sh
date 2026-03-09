#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Browsing Data Task Setup ==="
echo "Task: Clear browsing history from the last hour while preserving older history"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq sqlite3 python3 bc || true

# Wait for environment to be ready
sleep 2

# Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
HISTORY_DB="${CHROME_PROFILE}/History"
COOKIES_DB="${CHROME_PROFILE}/Cookies"

# Ensure Chrome is stopped before we manipulate databases
echo "Stopping Chrome if running..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 3

# Ensure profile directory exists
mkdir -p "${CHROME_PROFILE}"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp"

# Function to convert Unix timestamp to Chrome WebKit timestamp
# Chrome uses microseconds since 1601-01-01 00:00:00 UTC
# Unix uses seconds since 1970-01-01 00:00:00 UTC
# Difference: 11644473600 seconds
chrome_timestamp() {
    local unix_ts=$1
    echo $(( (unix_ts + 11644473600) * 1000000 ))
}

# Calculate timestamps
NOW=$(date +%s)
ONE_HOUR_AGO=$((NOW - 3600))
TWO_HOURS_AGO=$((NOW - 7200))
ONE_DAY_AGO=$((NOW - 86400))
TWO_DAYS_AGO=$((NOW - 172800))
THREE_DAYS_AGO=$((NOW - 259200))

# Convert to Chrome timestamps
CHROME_NOW=$(chrome_timestamp $NOW)
CHROME_30_MIN_AGO=$(chrome_timestamp $((NOW - 1800)))
CHROME_45_MIN_AGO=$(chrome_timestamp $((NOW - 2700)))
CHROME_ONE_DAY_AGO=$(chrome_timestamp $ONE_DAY_AGO)
CHROME_TWO_DAYS_AGO=$(chrome_timestamp $TWO_DAYS_AGO)
CHROME_THREE_DAYS_AGO=$(chrome_timestamp $THREE_DAYS_AGO)

# Start Chrome briefly to initialize the profile
echo "Initializing Chrome profile..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Wait for Chrome to fully initialize
sleep 3

# Stop Chrome to manipulate databases safely
echo "Stopping Chrome to populate history database..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 3

# Now populate the History database with test data
echo "Populating history database with test entries..."

# Create backup of original history if it exists
if [ -f "${HISTORY_DB}" ]; then
    cp "${HISTORY_DB}" "${HISTORY_DB}.original"
fi

# Insert test history entries using sqlite3
# We need to insert into both 'urls' and 'visits' tables
sqlite3 "${HISTORY_DB}" <<EOF
-- Insert old history entries (should be preserved)
INSERT OR IGNORE INTO urls (id, url, title, visit_count, typed_count, last_visit_time, hidden)
VALUES 
    (100001, 'https://en.wikipedia.org/wiki/History', 'History - Wikipedia', 1, 0, ${CHROME_THREE_DAYS_AGO}, 0),
    (100002, 'https://github.com/trending', 'Trending - GitHub', 1, 0, ${CHROME_TWO_DAYS_AGO}, 0),
    (100003, 'https://news.ycombinator.com/', 'Hacker News', 1, 0, ${CHROME_ONE_DAY_AGO}, 0);

-- Insert recent history entries (should be deleted)
INSERT OR IGNORE INTO urls (id, url, title, visit_count, typed_count, last_visit_time, hidden)
VALUES 
    (100004, 'https://www.reddit.com/', 'Reddit - Dive into anything', 1, 0, ${CHROME_45_MIN_AGO}, 0),
    (100005, 'https://stackoverflow.com/questions', 'Questions - Stack Overflow', 1, 0, ${CHROME_30_MIN_AGO}, 0),
    (100006, 'https://www.example.com/recent', 'Example Domain Recent', 1, 0, ${CHROME_NOW}, 0);

-- Insert corresponding visit entries
INSERT OR IGNORE INTO visits (id, url, visit_time, from_visit, transition, segment_id)
VALUES 
    (200001, 100001, ${CHROME_THREE_DAYS_AGO}, 0, 805306368, 0),
    (200002, 100002, ${CHROME_TWO_DAYS_AGO}, 0, 805306368, 0),
    (200003, 100003, ${CHROME_ONE_DAY_AGO}, 0, 805306368, 0),
    (200004, 100004, ${CHROME_45_MIN_AGO}, 0, 805306368, 0),
    (200005, 100005, ${CHROME_30_MIN_AGO}, 0, 805306368, 0),
    (200006, 100006, ${CHROME_NOW}, 0, 805306368, 0);
EOF

echo "✓ History database populated with 6 entries (3 old, 3 recent)"

# Verify the entries were inserted
TOTAL_COUNT=$(sqlite3 "${HISTORY_DB}" "SELECT COUNT(*) FROM urls WHERE id >= 100001 AND id <= 100006;")
echo "Verified ${TOTAL_COUNT} test entries in database"

# Save the "before" state for verification
echo "Saving before state..."
cp "${HISTORY_DB}" /tmp/history_before.db
if [ -f "${COOKIES_DB}" ]; then
    cp "${COOKIES_DB}" /tmp/cookies_before.db
fi

# Store the cutoff timestamp for verification (1 hour ago)
echo "${CHROME_30_MIN_AGO}" > /tmp/history_cutoff_timestamp.txt

# Fix permissions
chown ga:ga /tmp/history_before.db
[ -f /tmp/cookies_before.db ] && chown ga:ga /tmp/cookies_before.db
chown ga:ga /tmp/history_cutoff_timestamp.txt

# Restart Chrome for the task
echo "Starting Chrome for task..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

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

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is ready with:"
echo "  - 3 old history entries (>1 day ago) - should be preserved"
echo "  - 3 recent history entries (<1 hour ago) - should be deleted"
echo "  - Task: Clear browsing history from last hour only"