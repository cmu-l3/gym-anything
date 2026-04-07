#!/bin/bash
set -e
echo "=== Setting up osw_delete_youtube_history task ==="

date +%s > /tmp/task_start_time.txt

pkill -f chrome || true
sleep 2

CDP_DIR="/home/ga/.config/google-chrome-cdp"
CHROME_DIR="/home/ga/.config/google-chrome"

for PROFILE_DIR in "$CDP_DIR" "$CHROME_DIR"; do
    if [ -d "$PROFILE_DIR" ]; then
        rm -rf "$PROFILE_DIR"
    fi
    mkdir -p "$PROFILE_DIR/Default"
    chown -R ga:ga "$PROFILE_DIR"

    # Write default Preferences
    cat > "$PROFILE_DIR/Default/Preferences" << 'PREFEOF'
{
    "browser": {
        "show_home_button": true
    },
    "homepage": "https://www.google.com",
    "homepage_is_newtabpage": false,
    "download": {
        "prompt_for_download": false,
        "default_directory": "/home/ga/Downloads"
    }
}
PREFEOF
    chown -R ga:ga "$PROFILE_DIR"
done

# Launch Chrome briefly to initialize the History database, then kill it
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 8

pkill -f chrome || true
sleep 3
pkill -9 -f chrome 2>/dev/null || true
sleep 2

# Inject YouTube and non-YouTube history entries into the History SQLite database
# Chrome uses WebKit/Chromium timestamps (microseconds since 1601-01-01)
# We calculate offsets from current time
for PROFILE_DIR in "$CDP_DIR" "$CHROME_DIR"; do
    HISTORY_DB="$PROFILE_DIR/Default/History"
    if [ -f "$HISTORY_DB" ]; then
        python3 << 'PYEOF'
import sqlite3
import time
import os

# Chrome timestamps: microseconds since 1601-01-01
# Offset from Unix epoch (1970-01-01) = 11644473600 seconds
CHROME_EPOCH_OFFSET = 11644473600

def unix_to_chrome(unix_ts):
    return int((unix_ts + CHROME_EPOCH_OFFSET) * 1000000)

now = time.time()

history_entries = [
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "Rick Astley - Never Gonna Give You Up", 3600),
    ("https://www.youtube.com/watch?v=9bZkp7q19f0", "PSY - GANGNAM STYLE M/V", 1631),
    ("https://www.youtube.com/watch?v=3tmd-ClpJxA", "Maroon 5 - Sugar", 900),
    ("https://www.nytimes.com/", "The New York Times", 300),
    ("https://www.youtube.com/watch?v=OPf0YbXqDm0", "Ed Sheeran - Shape of You", 1200),
    ("https://www.youtube.com/watch?v=JGwWNGJdvx8", "Taylor Swift - Shake It Off", 2400),
    ("https://www.bbc.co.uk/", "BBC", 1500),
    ("https://www.youtube.com/watch?v=2Vv-BfVoq4g", "Adele - Hello", 1800),
    ("https://www.youtube.com/watch?v=YQHsXMglC9A", "Katy Perry - Roar", 2100),
    ("https://www.cnn.com/", "CNN", 2700),
    ("https://www.youtube.com/watch?v=ru0K8uYEZWw", "Justin Bieber - Baby ft. Ludacris", 3200),
    ("https://www.nationalgeographic.com/", "National Geographic", 4000),
]

for profile_dir in ["/home/ga/.config/google-chrome-cdp", "/home/ga/.config/google-chrome"]:
    db_path = profile_dir + "/Default/History"
    if not os.path.exists(db_path):
        continue
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Ensure the urls table exists
    try:
        cursor.execute("SELECT count(*) FROM urls")
    except:
        cursor.execute("""CREATE TABLE IF NOT EXISTS urls (
            id INTEGER PRIMARY KEY,
            url TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT '',
            visit_count INTEGER NOT NULL DEFAULT 0,
            typed_count INTEGER NOT NULL DEFAULT 0,
            last_visit_time INTEGER NOT NULL DEFAULT 0,
            hidden INTEGER NOT NULL DEFAULT 0
        )""")
        cursor.execute("""CREATE TABLE IF NOT EXISTS visits (
            id INTEGER PRIMARY KEY,
            url INTEGER NOT NULL,
            visit_time INTEGER NOT NULL DEFAULT 0,
            from_visit INTEGER NOT NULL DEFAULT 0,
            transition INTEGER NOT NULL DEFAULT 0,
            segment_id INTEGER NOT NULL DEFAULT 0,
            visit_duration INTEGER NOT NULL DEFAULT 0
        )""")
    
    for url, title, offset_secs in history_entries:
        visit_time = unix_to_chrome(now - offset_secs)
        cursor.execute(
            "INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, 1, 0, ?, 0)",
            (url, title, visit_time)
        )
        url_id = cursor.lastrowid
        cursor.execute(
            "INSERT INTO visits (url, visit_time, from_visit, transition, segment_id, visit_duration) VALUES (?, ?, 0, 805306368, 0, 0)",
            (url_id, visit_time)
        )
    
    conn.commit()
    conn.close()
    print(f"Injected {len(history_entries)} history entries into {db_path}")
PYEOF
    else
        echo "No History DB found at $HISTORY_DB, creating one..."
        python3 << PYEOF2
import sqlite3
import time
import os

CHROME_EPOCH_OFFSET = 11644473600

def unix_to_chrome(unix_ts):
    return int((unix_ts + CHROME_EPOCH_OFFSET) * 1000000)

now = time.time()
db_path = "${HISTORY_DB}"

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("""CREATE TABLE IF NOT EXISTS urls (
    id INTEGER PRIMARY KEY,
    url TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    visit_count INTEGER NOT NULL DEFAULT 0,
    typed_count INTEGER NOT NULL DEFAULT 0,
    last_visit_time INTEGER NOT NULL DEFAULT 0,
    hidden INTEGER NOT NULL DEFAULT 0
)""")
cursor.execute("""CREATE TABLE IF NOT EXISTS visits (
    id INTEGER PRIMARY KEY,
    url INTEGER NOT NULL,
    visit_time INTEGER NOT NULL DEFAULT 0,
    from_visit INTEGER NOT NULL DEFAULT 0,
    transition INTEGER NOT NULL DEFAULT 0,
    segment_id INTEGER NOT NULL DEFAULT 0,
    visit_duration INTEGER NOT NULL DEFAULT 0
)""")

history_entries = [
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "Rick Astley - Never Gonna Give You Up", 3600),
    ("https://www.youtube.com/watch?v=9bZkp7q19f0", "PSY - GANGNAM STYLE M/V", 1631),
    ("https://www.youtube.com/watch?v=3tmd-ClpJxA", "Maroon 5 - Sugar", 900),
    ("https://www.nytimes.com/", "The New York Times", 300),
    ("https://www.youtube.com/watch?v=OPf0YbXqDm0", "Ed Sheeran - Shape of You", 1200),
    ("https://www.youtube.com/watch?v=JGwWNGJdvx8", "Taylor Swift - Shake It Off", 2400),
    ("https://www.bbc.co.uk/", "BBC", 1500),
    ("https://www.youtube.com/watch?v=2Vv-BfVoq4g", "Adele - Hello", 1800),
    ("https://www.youtube.com/watch?v=YQHsXMglC9A", "Katy Perry - Roar", 2100),
    ("https://www.cnn.com/", "CNN", 2700),
    ("https://www.youtube.com/watch?v=ru0K8uYEZWw", "Justin Bieber - Baby ft. Ludacris", 3200),
    ("https://www.nationalgeographic.com/", "National Geographic", 4000),
]

for url, title, offset_secs in history_entries:
    visit_time = unix_to_chrome(now - offset_secs)
    cursor.execute(
        "INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, 1, 0, ?, 0)",
        (url, title, visit_time)
    )
    url_id = cursor.lastrowid
    cursor.execute(
        "INSERT INTO visits (url, visit_time, from_visit, transition, segment_id, visit_duration) VALUES (?, ?, 0, 805306368, 0, 0)",
        (url_id, visit_time)
    )

conn.commit()
conn.close()
print(f"Created History DB with {len(history_entries)} entries at {db_path}")
PYEOF2
    fi
    chown -R ga:ga "$PROFILE_DIR"
done

# Re-launch Chrome
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
sleep 1

DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
