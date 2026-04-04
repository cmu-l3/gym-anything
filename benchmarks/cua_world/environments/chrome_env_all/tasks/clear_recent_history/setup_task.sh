#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Recent History Task Setup ==="
echo "Task: Selectively clear browsing history from last 24 hours"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python libraries for history manipulation
pip3 install -q pytz 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is NOT running so we can manipulate the database
echo "Ensuring Chrome is stopped for database setup..."
pkill -f "chrome.*remote-debugging-port" || true
pkill -9 -f "google-chrome" || true
sleep 2

# Define Chrome profile paths
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
ALT_PROFILE="/home/ga/.config/google-chrome/Default"

# Use the profile that exists or create it
if [ -d "$CHROME_PROFILE" ]; then
    PROFILE_DIR="$CHROME_PROFILE"
elif [ -d "$ALT_PROFILE" ]; then
    PROFILE_DIR="$ALT_PROFILE"
else
    PROFILE_DIR="$CHROME_PROFILE"
    mkdir -p "$PROFILE_DIR"
    chown -R ga:ga "$(dirname $PROFILE_DIR)"
fi

echo "Using Chrome profile: $PROFILE_DIR"

# Create Python script to populate history with timestamps
cat > /tmp/populate_history.py << 'EOFPYTHON'
#!/usr/bin/env python3
"""
Populate Chrome history with test entries spanning multiple time periods
"""
import sqlite3
import sys
from datetime import datetime, timedelta

def datetime_to_chrome_timestamp(dt):
    """Convert Python datetime to Chrome timestamp (microseconds since 1601-01-01)"""
    epoch_start = datetime(1601, 1, 1)
    delta = dt - epoch_start
    return int(delta.total_seconds() * 1000000)

def populate_history(db_path):
    """Populate history database with test entries"""
    
    # Test URLs for different time periods
    recent_urls = [
        ("https://news.ycombinator.com/", "Hacker News"),
        ("https://www.reddit.com/r/programming", "r/programming"),
        ("https://twitter.com/", "Twitter"),
        ("https://www.linkedin.com/feed/", "LinkedIn Feed"),
        ("https://medium.com/", "Medium"),
        ("https://dev.to/", "DEV Community"),
        ("https://techcrunch.com/", "TechCrunch"),
        ("https://arstechnica.com/", "Ars Technica"),
        ("https://www.theverge.com/", "The Verge"),
        ("https://news.google.com/", "Google News"),
        ("https://www.bbc.com/news", "BBC News"),
        ("https://www.cnn.com/", "CNN"),
    ]
    
    older_urls = [
        ("https://docs.python.org/3/library/", "Python Standard Library"),
        ("https://github.com/python/cpython", "CPython GitHub"),
        ("https://stackoverflow.com/questions/tagged/python", "Python Questions"),
        ("https://realpython.com/", "Real Python"),
        ("https://www.tensorflow.org/", "TensorFlow"),
        ("https://pytorch.org/docs/", "PyTorch Documentation"),
        ("https://numpy.org/doc/", "NumPy Documentation"),
        ("https://pandas.pydata.org/docs/", "Pandas Documentation"),
        ("https://scikit-learn.org/", "Scikit-learn"),
        ("https://jupyter.org/", "Jupyter"),
        ("https://www.w3schools.com/python/", "W3Schools Python"),
        ("https://www.programiz.com/python-programming", "Programiz Python"),
        ("https://www.geeksforgeeks.org/python-programming-language/", "GeeksforGeeks Python"),
        ("https://www.tutorialspoint.com/python/", "TutorialsPoint Python"),
        ("https://docs.djangoproject.com/", "Django Documentation"),
        ("https://flask.palletsprojects.com/", "Flask Documentation"),
        ("https://fastapi.tiangolo.com/", "FastAPI Documentation"),
        ("https://www.sqlalchemy.org/", "SQLAlchemy"),
        ("https://www.postgresql.org/docs/", "PostgreSQL Documentation"),
        ("https://redis.io/documentation", "Redis Documentation"),
    ]
    
    ancient_urls = [
        ("https://www.amazon.com/", "Amazon"),
        ("https://www.ebay.com/", "eBay"),
        ("https://www.etsy.com/", "Etsy"),
        ("https://www.target.com/", "Target"),
        ("https://www.walmart.com/", "Walmart"),
        ("https://www.bestbuy.com/", "Best Buy"),
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "YouTube Video"),
        ("https://www.netflix.com/", "Netflix"),
        ("https://www.spotify.com/", "Spotify"),
        ("https://www.wikipedia.org/", "Wikipedia"),
    ]
    
    now = datetime.now()
    
    # Connect to database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Create tables if they don't exist (Chrome schema)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS urls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url LONGVARCHAR NOT NULL,
            title LONGVARCHAR,
            visit_count INTEGER DEFAULT 0 NOT NULL,
            typed_count INTEGER DEFAULT 0 NOT NULL,
            last_visit_time INTEGER NOT NULL,
            hidden INTEGER DEFAULT 0 NOT NULL
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL,
            from_visit INTEGER,
            transition INTEGER DEFAULT 0 NOT NULL,
            segment_id INTEGER,
            visit_duration INTEGER DEFAULT 0 NOT NULL
        )
    """)
    
    url_id = 1
    visit_id = 1
    
    # Add recent entries (last 24 hours)
    print(f"Adding {len(recent_urls)} recent entries (last 24 hours)...")
    for url, title in recent_urls:
        # Random time in last 24 hours
        hours_ago = 0.5 + (23.5 * (recent_urls.index((url, title)) / len(recent_urls)))
        visit_time = now - timedelta(hours=hours_ago)
        chrome_ts = datetime_to_chrome_timestamp(visit_time)
        
        cursor.execute("""
            INSERT INTO urls (id, url, title, visit_count, typed_count, last_visit_time, hidden)
            VALUES (?, ?, ?, 1, 0, ?, 0)
        """, (url_id, url, title, chrome_ts))
        
        cursor.execute("""
            INSERT INTO visits (id, url, visit_time, from_visit, transition, visit_duration)
            VALUES (?, ?, ?, NULL, 0, 30000000)
        """, (visit_id, url_id, chrome_ts))
        
        url_id += 1
        visit_id += 1
    
    # Add older entries (2-7 days ago)
    print(f"Adding {len(older_urls)} older entries (2-7 days ago)...")
    for url, title in older_urls:
        # Random time 2-7 days ago
        days_ago = 2 + (5 * (older_urls.index((url, title)) / len(older_urls)))
        visit_time = now - timedelta(days=days_ago)
        chrome_ts = datetime_to_chrome_timestamp(visit_time)
        
        cursor.execute("""
            INSERT INTO urls (id, url, title, visit_count, typed_count, last_visit_time, hidden)
            VALUES (?, ?, ?, 1, 0, ?, 0)
        """, (url_id, url, title, chrome_ts))
        
        cursor.execute("""
            INSERT INTO visits (id, url, visit_time, from_visit, transition, visit_duration)
            VALUES (?, ?, ?, NULL, 0, 45000000)
        """, (visit_id, url_id, chrome_ts))
        
        url_id += 1
        visit_id += 1
    
    # Add ancient entries (8-14 days ago)
    print(f"Adding {len(ancient_urls)} ancient entries (8-14 days ago)...")
    for url, title in ancient_urls:
        # Random time 8-14 days ago
        days_ago = 8 + (6 * (ancient_urls.index((url, title)) / len(ancient_urls)))
        visit_time = now - timedelta(days=days_ago)
        chrome_ts = datetime_to_chrome_timestamp(visit_time)
        
        cursor.execute("""
            INSERT INTO urls (id, url, title, visit_count, typed_count, last_visit_time, hidden)
            VALUES (?, ?, ?, 1, 0, ?, 0)
        """, (url_id, url, title, chrome_ts))
        
        cursor.execute("""
            INSERT INTO visits (id, url, visit_time, from_visit, transition, visit_duration)
            VALUES (?, ?, ?, NULL, 0, 60000000)
        """, (visit_id, url_id, chrome_ts))
        
        url_id += 1
        visit_id += 1
    
    conn.commit()
    conn.close()
    
    print(f"✓ Successfully populated history with {url_id - 1} entries")
    return True

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: populate_history.py <history_db_path>")
        sys.exit(1)
    
    db_path = sys.argv[1]
    populate_history(db_path)
EOFPYTHON

chmod +x /tmp/populate_history.py

# Create/initialize history database
HISTORY_DB="$PROFILE_DIR/History"
echo "Setting up history database: $HISTORY_DB"

# Remove existing history if present
if [ -f "$HISTORY_DB" ]; then
    echo "Removing existing history database..."
    rm -f "$HISTORY_DB"
    rm -f "${HISTORY_DB}-journal"
fi

# Populate history with test data
echo "Populating history with test data..."
python3 /tmp/populate_history.py "$HISTORY_DB"

# Ensure proper ownership
chown ga:ga "$HISTORY_DB" 2>/dev/null || true

# Create a snapshot of the initial history for verification
echo "Creating initial history snapshot for verification..."
mkdir -p /tmp/history_verification
cp "$HISTORY_DB" /tmp/history_verification/History_before.db
chown -R ga:ga /tmp/history_verification

# Verify the database is valid
echo "Verifying history database..."
ENTRY_COUNT=$(sqlite3 "$HISTORY_DB" "SELECT COUNT(*) FROM urls;" 2>/dev/null || echo "0")
echo "✓ History database contains $ENTRY_COUNT entries"

# Now start Chrome with the populated history
echo "Starting Chrome with populated history..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://settings" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# Focus desktop and Chrome window
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to Settings page to make it easier for agent
echo "Navigating to chrome://settings..."
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'chrome://settings'" || true
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

echo "=== Setup complete ==="
echo "Chrome is ready with populated history"
echo "Agent should:"
echo "  1. Press Ctrl+Shift+Del OR navigate to chrome://settings/clearBrowserData"
echo "  2. Select 'Last 24 hours' from time range dropdown"
echo "  3. Ensure 'Browsing history' checkbox is enabled"
echo "  4. Ensure other checkboxes (cookies, cache) are disabled"
echo "  5. Click 'Clear data' button"
echo ""
echo "Initial history: $ENTRY_COUNT entries"