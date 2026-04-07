#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Port Control Terminal Setup Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop Chrome to safely modify profile
echo "Stopping Chrome..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# We target the CDP profile directory as it's used by the environment's launch_chrome.sh
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp"

# Create required download directory
mkdir -p "/home/ga/Documents/Vessel_Manifests"
chown ga:ga "/home/ga/Documents/Vessel_Manifests"

# Provide the protocol document
cat > "/home/ga/Desktop/port_terminal_protocol.txt" << 'EOF'
PORT AUTHORITY TERMINAL BROWSER CONFIGURATION PROTOCOL
======================================================
1. Remove all personal and entertainment bookmarks.
2. Organize maritime bookmarks into folders:
   - AIS & Tracking
   - Metocean Data
   - Port Operations
   - Emergency & USCG
3. Delete personal browsing history; preserve maritime history.
4. Set startup pages: marinetraffic.com and tidesandcurrents.noaa.gov
5. Disable "Intensive wake up throttling" in chrome://flags
6. Add custom search engine: keyword 'imo' -> https://www.vesselfinder.com/vessels?name=%s
7. Block all notifications globally.
8. Set download path to ~/Documents/Vessel_Manifests.
EOF
chown ga:ga "/home/ga/Desktop/port_terminal_protocol.txt"

# Generate Bookmarks and History using Python
echo "Generating Chrome data (Bookmarks and History)..."
python3 << 'PYEOF'
import json
import sqlite3
import time
import uuid
import os

profile_dir = "/home/ga/.config/google-chrome-cdp/Default"
os.makedirs(profile_dir, exist_ok=True)

chrome_time = int((time.time() + 11644473600) * 1000000)

maritime_sites = [
    ("MarineTraffic", "https://www.marinetraffic.com/"),
    ("VesselFinder", "https://www.vesselfinder.com/"),
    ("MyShipTracking", "https://www.myshiptracking.com/"),
    ("VesselTracker", "https://www.vesseltracker.com/"),
    ("NOAA Tides", "https://tidesandcurrents.noaa.gov/"),
    ("NWS Marine Weather", "https://weather.gov/marine"),
    ("National Data Buoy Center", "https://www.ndbc.noaa.gov/"),
    ("Ocean Prediction Center", "https://ocean.weather.gov/"),
    ("AAPA Ports", "https://www.aapa-ports.org/"),
    ("CargoSmart", "https://www.cargosmart.ai/"),
    ("BIC Code", "https://www.bic-code.org/"),
    ("USCG Home", "https://www.uscg.mil/"),
    ("USCG Navigation Center", "https://www.navcen.uscg.gov/"),
    ("USCG DCO", "https://www.dco.uscg.mil/")
]

personal_sites = [
    ("Netflix", "https://www.netflix.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Twitter", "https://twitter.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Steam", "https://store.steampowered.com/"),
    ("Hulu", "https://www.hulu.com/"),
    ("TikTok", "https://www.tiktok.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Instagram", "https://www.instagram.com/")
]

# Create Bookmarks
children = []
bid = 10
for name, url in maritime_sites + personal_sites:
    children.append({
        "date_added": str(chrome_time - bid * 10000000),
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": url
    })
    bid += 1

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_time),
            "date_modified": str(chrome_time),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)

# Create History SQLite DB
db_path = os.path.join(profile_dir, "History")
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute('''CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)''')

# Populate History (30 maritime, 20 personal entries)
for i in range(3):
    for name, url in maritime_sites:
        cursor.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, ?, ?)",
                       (url + f"?v={i}", name, 1, chrome_time - (i * 1000000)))
for i in range(2):
    for name, url in personal_sites:
        cursor.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, ?, ?)",
                       (url + f"?v={i}", name, 1, chrome_time - (i * 2000000)))

conn.commit()
conn.close()
PYEOF

chown -R ga:ga "$CHROME_PROFILE"

# Start Chrome (using the environment's CDP launch script)
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://newtab &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="