#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective History Cleanup Task Setup ==="
echo "Task: Selectively delete shopping-related history while preserving other entries"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Wait for environment to be ready
sleep 2

# Close Chrome if running (need to modify History database)
echo "Stopping Chrome to inject test history data..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 3

# Ensure Chrome is fully stopped
pkill -9 -f "google-chrome" || true
sleep 1

# Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome-cdp/

# Path to History database
HISTORY_DB="$CHROME_PROFILE/History"

# Create History database if it doesn't exist or backup existing
if [ -f "$HISTORY_DB" ]; then
    echo "Backing up existing History database..."
    cp "$HISTORY_DB" "$HISTORY_DB.backup"
else
    echo "Creating new History database..."
    # Create minimal History database structure
    sqlite3 "$HISTORY_DB" <<EOF
CREATE TABLE urls(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url LONGVARCHAR,
  title LONGVARCHAR,
  visit_count INTEGER DEFAULT 0 NOT NULL,
  typed_count INTEGER DEFAULT 0 NOT NULL,
  last_visit_time INTEGER NOT NULL,
  hidden INTEGER DEFAULT 0 NOT NULL
);
CREATE TABLE visits(
  id INTEGER PRIMARY KEY,
  url INTEGER NOT NULL,
  visit_time INTEGER NOT NULL,
  from_visit INTEGER,
  transition INTEGER DEFAULT 0 NOT NULL
);
CREATE INDEX visits_url_index ON visits (url);
CREATE INDEX visits_time_index ON visits (visit_time);
EOF
fi

# Inject test history entries
echo "Injecting test history entries..."

# Chrome timestamp: microseconds since January 1, 1601 UTC
# Calculate base timestamp (now minus various hours)
CURRENT_TIME=$(date +%s)
BASE_TIMESTAMP=$(( (CURRENT_TIME + 11644473600) * 1000000 ))

# Shopping-related URLs (to be deleted)
sqlite3 "$HISTORY_DB" <<EOF
-- Shopping URLs (5-7 entries)
INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES
  ('https://www.amazon.com/', 'Amazon.com: Online Shopping for Electronics, Apparel, Computers', 3, $((BASE_TIMESTAMP - 3600000000)), 0),
  ('https://www.amazon.com/s?k=laptop', 'Amazon.com: laptop', 2, $((BASE_TIMESTAMP - 3000000000)), 0),
  ('https://www.ebay.com/', 'Electronics, Cars, Fashion, Collections & More | eBay', 2, $((BASE_TIMESTAMP - 7200000000)), 0),
  ('https://www.etsy.com/', 'Etsy - Shop for handmade, vintage, custom, and unique gifts', 1, $((BASE_TIMESTAMP - 10800000000)), 0),
  ('https://shopping.google.com/', 'Google Shopping - Shop Online, Compare Prices & Where to Buy', 1, $((BASE_TIMESTAMP - 14400000000)), 0),
  ('https://www.walmart.com/', 'Walmart.com | Save Money. Live Better.', 2, $((BASE_TIMESTAMP - 18000000000)), 0);

-- News URLs (5-7 entries) - should be preserved
INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES
  ('https://www.bbc.com/news', 'BBC News - Home', 5, $((BASE_TIMESTAMP - 1800000000)), 0),
  ('https://www.cnn.com/', 'CNN - Breaking News, Latest News and Videos', 4, $((BASE_TIMESTAMP - 5400000000)), 0),
  ('https://www.reuters.com/', 'Reuters | Breaking International News & Views', 3, $((BASE_TIMESTAMP - 9000000000)), 0),
  ('https://www.theguardian.com/', 'The Guardian | Latest news, sport and opinion', 2, $((BASE_TIMESTAMP - 12600000000)), 0),
  ('https://www.nytimes.com/', 'The New York Times - Breaking News, US News, World News', 3, $((BASE_TIMESTAMP - 16200000000)), 0);

-- Educational URLs (5-7 entries) - should be preserved
INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES
  ('https://www.wikipedia.org/', 'Wikipedia', 8, $((BASE_TIMESTAMP - 2700000000)), 0),
  ('https://en.wikipedia.org/wiki/Machine_learning', 'Machine learning - Wikipedia', 3, $((BASE_TIMESTAMP - 6300000000)), 0),
  ('https://www.khanacademy.org/', 'Khan Academy | Free Online Courses, Lessons & Practice', 4, $((BASE_TIMESTAMP - 9900000000)), 0),
  ('https://www.coursera.org/', 'Coursera | Degrees, Certificates, & Free Online Courses', 2, $((BASE_TIMESTAMP - 13500000000)), 0),
  ('https://www.edx.org/', 'edX | Build new skills. Advance your career.', 2, $((BASE_TIMESTAMP - 17100000000)), 0),
  ('https://stackoverflow.com/questions/tagged/python', 'Newest python questions - Stack Overflow', 5, $((BASE_TIMESTAMP - 20700000000)), 0);

-- Social media URLs (3-5 entries) - should be preserved
INSERT INTO urls (url, title, visit_count, last_visit_time, hidden) VALUES
  ('https://www.reddit.com/', 'Reddit - Dive into anything', 6, $((BASE_TIMESTAMP - 4500000000)), 0),
  ('https://www.reddit.com/r/programming/', 'r/programming - Reddit', 4, $((BASE_TIMESTAMP - 8100000000)), 0),
  ('https://twitter.com/', 'X. It'\''s what'\''s happening', 3, $((BASE_TIMESTAMP - 11700000000)), 0),
  ('https://www.linkedin.com/', 'LinkedIn: Log In or Sign Up', 2, $((BASE_TIMESTAMP - 15300000000)), 0);
EOF

# Set proper permissions
chown ga:ga "$HISTORY_DB"
chmod 644 "$HISTORY_DB"

echo "✓ Test history entries injected:"
echo "  - 6 shopping-related URLs (to be deleted)"
echo "  - 5 news URLs (to be preserved)"
echo "  - 6 educational URLs (to be preserved)"
echo "  - 4 social media URLs (to be preserved)"
echo "  Total: 21 history entries"

# Count entries for verification
TOTAL_COUNT=$(sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM urls;")
SHOPPING_COUNT=$(sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM urls WHERE url LIKE '%shop%' OR url LIKE '%amazon%' OR url LIKE '%ebay%' OR url LIKE '%etsy%' OR url LIKE '%walmart%';")
echo "  Verified: $TOTAL_COUNT total entries, $SHOPPING_COUNT shopping entries"

# Save initial counts for verification
echo "$TOTAL_COUNT" > /tmp/initial_history_total.txt
echo "$SHOPPING_COUNT" > /tmp/initial_shopping_count.txt

# Now start Chrome
echo "Starting Chrome..."
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

# Navigate to starting page (Google)
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

echo "=== Setup complete ==="
echo "Chrome is ready with pre-populated history"
echo "Agent should now:"
echo "  1. Navigate to chrome://history (Ctrl+H or type in address bar)"
echo "  2. Search for 'shop' or 'shopping' in the search box"
echo "  3. Select all shopping-related entries"
echo "  4. Click 'Delete' or 'Remove selected items'"
echo "  5. Verify shopping entries are gone but other history remains"