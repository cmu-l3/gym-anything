#!/bin/bash
set -e

echo "[Setup] Starting Clear Browsing Data task setup..."

# Kill any existing Chrome processes
echo "[Setup] Stopping any existing Chrome processes..."
pkill -9 chrome || true
pkill -9 chromedriver || true
sleep 2

# Define Chrome profile path
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
HISTORY_DB="${CHROME_PROFILE}/History"

# Ensure Chrome profile directory exists
mkdir -p "${CHROME_PROFILE}"

echo "[Setup] Creating test browsing history with timestamps..."

# Create a Python script to populate history database
cat > /tmp/populate_history.py << 'PYTHON_SCRIPT'
import sqlite3
import os
from datetime import datetime, timedelta

# Chrome WebKit timestamp: microseconds since January 1, 1601 UTC
def datetime_to_chrome_timestamp(dt):
    """Convert datetime to Chrome WebKit timestamp"""
    epoch_start = datetime(1601, 1, 1)
    delta = dt - epoch_start
    return int(delta.total_seconds() * 1000000)

def create_history_database(db_path):
    """Create and populate Chrome History database with test data"""
    
    # Remove existing database
    if os.path.exists(db_path):
        os.remove(db_path)
    
    # Create new database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Create necessary tables (simplified schema)
    cursor.execute("""
        CREATE TABLE urls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            title TEXT,
            visit_count INTEGER DEFAULT 0,
            typed_count INTEGER DEFAULT 0,
            last_visit_time INTEGER NOT NULL,
            hidden INTEGER DEFAULT 0
        )
    """)
    
    cursor.execute("""
        CREATE TABLE visits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL,
            from_visit INTEGER,
            transition INTEGER DEFAULT 0
        )
    """)
    
    # Create indexes
    cursor.execute("CREATE INDEX urls_url_index ON urls(url)")
    cursor.execute("CREATE INDEX visits_url_index ON visits(url)")
    cursor.execute("CREATE INDEX visits_time_index ON visits(visit_time)")
    
    now = datetime.now()
    
    # Old entries (should be preserved after clearing "last hour")
    old_entries = [
        ("https://example.com", "Example Domain", now - timedelta(days=3)),
        ("https://wikipedia.org", "Wikipedia", now - timedelta(days=2)),
        ("https://github.com", "GitHub", now - timedelta(days=1)),
        ("https://python.org", "Python.org", now - timedelta(hours=25)),
        ("https://stackoverflow.com", "Stack Overflow", now - timedelta(hours=24, minutes=5)),
    ]
    
    # Recent entries (should be deleted when clearing "last hour")
    recent_entries = [
        ("https://news.ycombinator.com", "Hacker News", now - timedelta(minutes=45)),
        ("https://reddit.com", "Reddit", now - timedelta(minutes=30)),
        ("https://twitter.com", "Twitter", now - timedelta(minutes=15)),
        ("https://linkedin.com", "LinkedIn", now - timedelta(minutes=5)),
    ]
    
    url_id = 1
    visit_id = 1
    
    # Insert old entries
    for url, title, visit_time in old_entries:
        chrome_timestamp = datetime_to_chrome_timestamp(visit_time)
        cursor.execute("""
            INSERT INTO urls (id, url, title, visit_count, last_visit_time)
            VALUES (?, ?, ?, 1, ?)
        """, (url_id, url, title, chrome_timestamp))
        
        cursor.execute("""
            INSERT INTO visits (id, url, visit_time)
            VALUES (?, ?, ?)
        """, (visit_id, url_id, chrome_timestamp))
        
        url_id += 1
        visit_id += 1
    
    # Insert recent entries
    for url, title, visit_time in recent_entries:
        chrome_timestamp = datetime_to_chrome_timestamp(visit_time)
        cursor.execute("""
            INSERT INTO urls (id, url, title, visit_count, last_visit_time)
            VALUES (?, ?, ?, 1, ?)
        """, (url_id, url, title, chrome_timestamp))
        
        cursor.execute("""
            INSERT INTO visits (id, url, visit_time)
            VALUES (?, ?, ?)
        """, (visit_id, url_id, chrome_timestamp))
        
        url_id += 1
        visit_id += 1
    
    conn.commit()
    conn.close()
    
    print(f"Created history database with {len(old_entries)} old entries and {len(recent_entries)} recent entries")

if __name__ == "__main__":
    db_path = "/home/ga/.config/google-chrome/Default/History"
    create_history_database(db_path)
PYTHON_SCRIPT

# Run the Python script to create history
python3 /tmp/populate_history.py

# Set proper permissions
chown -R ga:ga "${CHROME_PROFILE}"
chmod 644 "${HISTORY_DB}"

echo "[Setup] Test history database created successfully"

# Create a bookmark to ensure bookmarks aren't affected
BOOKMARKS_FILE="${CHROME_PROFILE}/Bookmarks"
if [ ! -f "${BOOKMARKS_FILE}" ]; then
    echo "[Setup] Creating initial bookmarks..."
    cat > "${BOOKMARKS_FILE}" << 'EOF'
{
   "checksum": "0000000000000000000000000000000000000000",
   "roots": {
      "bookmark_bar": {
         "children": [ {
            "date_added": "13300000000000000",
            "guid": "00000000-0000-0000-0000-000000000001",
            "id": "5",
            "name": "Important Sites",
            "type": "url",
            "url": "https://important-site.com"
         } ],
         "date_added": "13300000000000000",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000002",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13300000000000000",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000003",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13300000000000000",
         "date_modified": "0",
         "guid": "00000000-0000-0000-0000-000000000004",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
    chown ga:ga "${BOOKMARKS_FILE}"
fi

# Start Chrome for the user
echo "[Setup] Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh" &

# Wait for Chrome to start
sleep 5

# Verify Chrome is running
if pgrep -u ga chrome > /dev/null; then
    echo "[Setup] Chrome started successfully"
else
    echo "[Setup] Warning: Chrome may not have started properly"
fi

echo "[Setup] Setup complete. Agent can now perform the task."
echo "[Setup] Task: Press Ctrl+Shift+Del, select 'Last hour', check only 'Browsing history', and click 'Clear data'"