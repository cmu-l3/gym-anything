#!/usr/bin/env bash
# set -euo pipefail

echo "=== OSWorld Chrome Task Setup: 44ee5668-ecd5-4366-a6ce-c1c9b8d4e938 ==="
echo "Task: I am looking for an website address I accessed a month ago, but Youtube websites which take almost all of my browsing history are interrupting my search. This is too annoying. I want to remove all my Youtube browsing history first to facilitate my search. Could you help me clear browsing history from Youtube?"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq sqlite3 python3 || true

# Seed browsing history
echo "Seeding Chrome browsing history..."

# First, ensure Chrome profile exists by starting Chrome briefly
echo "Ensuring Chrome profile exists..."
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Starting Chrome to create profile..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
    # Kill it to seed history
    pkill chrome || true
    sleep 3
fi

# Make sure Chrome is stopped before seeding history
pkill chrome || true
sleep 2

# Create Python script to seed history
cat > /tmp/seed_history.py << 'PYTHON_EOF'
#!/usr/bin/env python3
import sqlite3
import json
import time
import os
from pathlib import Path

# Chrome history location
chrome_profile = Path("/home/ga/.config/google-chrome-cdp/Default")
history_db = chrome_profile / "History"

# Ensure profile directory exists
chrome_profile.mkdir(parents=True, exist_ok=True)

# If History DB doesn't exist, create it with proper schema
if not history_db.exists():
    print(f"Creating new History database at {history_db}")
    conn = sqlite3.connect(str(history_db))
    cursor = conn.cursor()

    # Create urls table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS urls(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url LONGVARCHAR,
            title LONGVARCHAR,
            visit_count INTEGER DEFAULT 0 NOT NULL,
            typed_count INTEGER DEFAULT 0 NOT NULL,
            last_visit_time INTEGER NOT NULL,
            hidden INTEGER DEFAULT 0 NOT NULL
        )
    """)

    # Create visits table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS visits(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL,
            from_visit INTEGER,
            transition INTEGER DEFAULT 0 NOT NULL
        )
    """)

    conn.commit()
    conn.close()
    print("History database schema created")


# History entries to add
history_entries = [
    {
        "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "title": "Rick Astley - Never Gonna Give You Up (Official Music Video)",
        "visit_time_from_now_in_seconds": 3600
    },
    {
        "url": "https://www.youtube.com/watch?v=9bZkp7q19f0",
        "title": "PSY - GANGNAM STYLE(\uac15\ub0a8\uc2a4\ud0c0\uc77c) M/V",
        "visit_time_from_now_in_seconds": 1631
    },
    {
        "url": "https://www.youtube.com/watch?v=3tmd-ClpJxA",
        "title": "Maroon 5 - Sugar (Official Music Video)",
        "visit_time_from_now_in_seconds": 900
    },
    {
        "url": "https://www.nytimes.com/",
        "title": "The New York Times",
        "visit_time_from_now_in_seconds": 300
    },
    {
        "url": "https://www.youtube.com/watch?v=OPf0YbXqDm0",
        "title": "Ed Sheeran - Shape of You [Official Music Video]",
        "visit_time_from_now_in_seconds": 1200
    },
    {
        "url": "https://www.youtube.com/watch?v=JGwWNGJdvx8",
        "title": "Taylor Swift - Shake It Off",
        "visit_time_from_now_in_seconds": 2400
    },
    {
        "url": "https://www.bbc.co.uk/",
        "title": "BBC",
        "visit_time_from_now_in_seconds": 1500
    },
    {
        "url": "https://www.youtube.com/watch?v=2Vv-BfVoq4g",
        "title": "Adele - Hello",
        "visit_time_from_now_in_seconds": 1800
    },
    {
        "url": "https://www.youtube.com/watch?v=YQHsXMglC9A",
        "title": "Katy Perry - Roar (Official Music Video)",
        "visit_time_from_now_in_seconds": 2100
    },
    {
        "url": "https://www.cnn.com/",
        "title": "CNN",
        "visit_time_from_now_in_seconds": 2700
    },
    {
        "url": "https://www.youtube.com/watch?v=ru0K8uYEZWw",
        "title": "Justin Bieber - Baby ft. Ludacris (Official Music Video)",
        "visit_time_from_now_in_seconds": 3200
    },
    {
        "url": "https://www.youtube.com/watch?v=9bZkp7q19f0",
        "title": "PSY - GANGNAM STYLE(\uac15\ub0a8\uc2a4\ud0c0\uc77c) M/V",
        "visit_time_from_now_in_seconds": 3700
    },
    {
        "url": "https://www.nationalgeographic.com/",
        "title": "National Geographic",
        "visit_time_from_now_in_seconds": 4000
    },
    {
        "url": "https://www.youtube.com/watch?v=OPf0YbXqDm0",
        "title": "Ed Sheeran - Shape of You [Official Music Video]",
        "visit_time_from_now_in_seconds": 4300
    },
    {
        "url": "https://www.youtube.com/watch?v=JGwWNGJdvx8",
        "title": "Taylor Swift - Shake It Off",
        "visit_time_from_now_in_seconds": 4700
    },
    {
        "url": "https://www.bbc.co.uk/",
        "title": "BBC",
        "visit_time_from_now_in_seconds": 5000
    },
    {
        "url": "https://www.youtube.com/watch?v=2Vv-BfVoq4g",
        "title": "Adele - Hello",
        "visit_time_from_now_in_seconds": 5300
    },
    {
        "url": "https://www.youtube.com/watch?v=YQHsXMglC9A",
        "title": "Katy Perry - Roar (Official Music Video)",
        "visit_time_from_now_in_seconds": 5600
    },
    {
        "url": "https://www.cnn.com/",
        "title": "CNN",
        "visit_time_from_now_in_seconds": 5900
    },
    {
        "url": "https://www.youtube.com/watch?v=ru0K8uYEZWw",
        "title": "Justin Bieber - Baby ft. Ludacris (Official Music Video)",
        "visit_time_from_now_in_seconds": 6300
    },
    {
        "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "title": "Rick Astley - Never Gonna Give You Up (Official Music Video)",
        "visit_time_from_now_in_seconds": 6700
    },
    {
        "url": "https://www.nationalgeographic.com/",
        "title": "National Geographic",
        "visit_time_from_now_in_seconds": 7000
    },
    {
        "url": "https://www.youtube.com/watch?v=OPf0YbXqDm0",
        "title": "Ed Sheeran - Shape of You [Official Music Video]",
        "visit_time_from_now_in_seconds": 7300
    },
    {
        "url": "https://www.youtube.com/watch?v=JGwWNGJdvx8",
        "title": "Taylor Swift - Shake It Off",
        "visit_time_from_now_in_seconds": 7600
    },
    {
        "url": "https://www.bbc.co.uk/",
        "title": "BBC",
        "visit_time_from_now_in_seconds": 7900
    },
    {
        "url": "https://www.youtube.com/watch?v=2Vv-BfVoq4g",
        "title": "Adele - Hello",
        "visit_time_from_now_in_seconds": 8200
    },
    {
        "url": "https://www.youtube.com/watch?v=YQHsXMglC9A",
        "title": "Katy Perry - Roar (Official Music Video)",
        "visit_time_from_now_in_seconds": 8500
    },
    {
        "url": "https://www.cnn.com/",
        "title": "CNN",
        "visit_time_from_now_in_seconds": 8800
    },
    {
        "url": "https://www.youtube.com/watch?v=ru0K8uYEZWw",
        "title": "Justin Bieber - Baby ft. Ludacris (Official Music Video)",
        "visit_time_from_now_in_seconds": 9100
    },
    {
        "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "title": "Rick Astley - Never Gonna Give You Up (Official Music Video)",
        "visit_time_from_now_in_seconds": 9400
    },
    {
        "url": "https://www.nationalgeographic.com/",
        "title": "National Geographic",
        "visit_time_from_now_in_seconds": 9700
    },
    {
        "url": "https://www.youtube.com/watch?v=OPf0YbXqDm0",
        "title": "Ed Sheeran - Shape of You [Official Music Video]",
        "visit_time_from_now_in_seconds": 10000
    },
    {
        "url": "https://www.youtube.com/watch?v=JGwWNGJdvx8",
        "title": "Taylor Swift - Shake It Off",
        "visit_time_from_now_in_seconds": 10300
    },
    {
        "url": "https://www.bbc.co.uk/",
        "title": "BBC",
        "visit_time_from_now_in_seconds": 10600
    },
    {
        "url": "https://www.youtube.com/watch?v=2Vv-BfVoq4g",
        "title": "Adele - Hello",
        "visit_time_from_now_in_seconds": 10900
    },
    {
        "url": "https://www.youtube.com/watch?v=YQHsXMglC9A",
        "title": "Katy Perry - Roar (Official Music Video)",
        "visit_time_from_now_in_seconds": 11200
    },
    {
        "url": "https://www.cnn.com/",
        "title": "CNN",
        "visit_time_from_now_in_seconds": 11500
    },
    {
        "url": "https://www.youtube.com/watch?v=ru0K8uYEZWw",
        "title": "Justin Bieber - Baby ft. Ludacris (Official Music Video)",
        "visit_time_from_now_in_seconds": 11800
    },
    {
        "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "title": "Rick Astley - Never Gonna Give You Up (Official Music Video)",
        "visit_time_from_now_in_seconds": 12100
    },
    {
        "url": "https://www.nationalgeographic.com/",
        "title": "National Geographic",
        "visit_time_from_now_in_seconds": 12400
    }
]

# Chrome uses WebKit time (microseconds since 1601-01-01)
WEBKIT_EPOCH = 11644473600000000  # microseconds

def current_webkit_time():
    """Convert current time to WebKit time"""
    return int((time.time() * 1000000) + WEBKIT_EPOCH)

# Stop Chrome if running
import subprocess
subprocess.run(["pkill", "chrome"], stderr=subprocess.DEVNULL)
time.sleep(2)

# Connect to history database
conn = sqlite3.connect(str(history_db))
cursor = conn.cursor()

# Add history entries
for entry in history_entries:
    url = entry["url"]
    title = entry["title"]
    visit_time_offset = entry["visit_time_from_now_in_seconds"]

    # Calculate visit time (past time)
    visit_time = current_webkit_time() - (visit_time_offset * 1000000)

    # Insert URL
    cursor.execute("""
        INSERT OR IGNORE INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden)
        VALUES (?, ?, 1, 0, ?, 0)
    """, (url, title, visit_time))

    url_id = cursor.lastrowid
    if url_id == 0:
        # URL already exists, get its ID
        cursor.execute("SELECT id FROM urls WHERE url = ?", (url,))
        result = cursor.fetchone()
        if result:
            url_id = result[0]

    # Insert visit
    cursor.execute("""
        INSERT INTO visits (url, visit_time, from_visit, transition)
        VALUES (?, ?, 0, 0)
    """, (url_id, visit_time))

conn.commit()
conn.close()

print(f"Added {len(history_entries)} history entries")
PYTHON_EOF

chmod +x /tmp/seed_history.py
python3 /tmp/seed_history.py
rm /tmp/seed_history.py

echo "✓ History seeding complete"
sleep 2

# Wait for environment to be ready
sleep 2

# Ensure Chrome is properly focused and on correct URL
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
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

# Navigate to the starting URL
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
echo "Chrome should be focused and on: https://www.google.com"
