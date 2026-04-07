#!/usr/bin/env bash
set -euo pipefail

echo "=== Backcountry Permit Desk Setup Task ==="
echo "Preparing browser environment..."

# Wait for environment to stabilize
sleep 2

# 1. Stop Chrome safely
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 2. Setup directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/Issued_Permits"
chown -R ga:ga /home/ga/Documents/Issued_Permits

# 3. Create the specification document
cat > "/home/ga/Desktop/ranger_station_browser_spec.txt" << 'SPEC_EOF'
BACKCOUNTRY PERMIT DESK - BROWSER SPECIFICATION v2.1
Target: Shared terminal on satellite connection

The previous seasonal caretaker left personal browsing data on this terminal.
You must sanitize it and configure it for emergency response and permit issuance.

REQUIREMENTS:

1. BOOKMARK SANITIZATION & ORGANIZATION
   - Delete ALL bookmarks related to entertainment or social media (TikTok, Instagram, Steam, Reddit, Netflix, Twitch, Spotify, Twitter/X, Pinterest, Facebook).
   - Organize the remaining legitimate work bookmarks into exactly 4 folders on the bookmark bar:
     * "Permit Systems" (Recreation.gov, NPS portal, etc.)
     * "Weather & Hazards" (NWS, Avalanche, AirNow)
     * "Mapping & Trails" (USGS Topo, CalTopo, ArcGIS, Gaia)
     * "NPS Resources" (NPS main, Leave No Trace)

2. HISTORY SANITIZATION
   - Purge all browsing history related to the entertainment/social media sites listed above.
   - Do NOT delete legitimate work history (NPS, weather, mapping, etc.), as rangers rely on autocomplete for fast access.

3. OFFLINE & LOW-BANDWIDTH OPTIMIZATIONS
   - In chrome://flags, enable "Show Saved Copy Button" (so we can view cached pages when satellite drops).
   - In chrome://flags, enable "Enable Offline Auto-Reload".
   - In Chrome Settings -> Privacy and security, disable "Preload pages for faster browsing and searching".
   - In Chrome Settings -> Site Settings, block "Background Sync" globally.

4. SEARCH & STARTUP
   - Add a custom search engine with the keyword 'trail' pointing to the NPS trail search URL:
     https://www.nps.gov/subjects/trails/search.htm?query=%s
   - Set the browser to open a specific set of pages on startup: https://www.weather.gov/ and https://www.recreation.gov/

5. DOWNLOADS
   - Set the default download location to ~/Documents/Issued_Permits
   - Disable "Ask where to save each file before downloading" (for rapid 1-click permit saving).
SPEC_EOF
chown ga:ga "/home/ga/Desktop/ranger_station_browser_spec.txt"

# 4. Generate Initial Bookmarks (Mixed work and junk)
echo "Generating Bookmarks..."
cat > "$CHROME_PROFILE/Bookmarks" << 'BM_EOF'
{
   "checksum": "0",
   "roots": {
      "bookmark_bar": {
         "children": [
            { "id": "101", "name": "TikTok", "type": "url", "url": "https://www.tiktok.com/" },
            { "id": "102", "name": "Recreation.gov", "type": "url", "url": "https://www.recreation.gov/" },
            { "id": "103", "name": "Instagram", "type": "url", "url": "https://www.instagram.com/" },
            { "id": "104", "name": "National Weather Service", "type": "url", "url": "https://www.weather.gov/" },
            { "id": "105", "name": "Steam", "type": "url", "url": "https://store.steampowered.com/" },
            { "id": "106", "name": "USGS Topo Maps", "type": "url", "url": "https://www.usgs.gov/core-science-systems/ngp/tnm-delivery" },
            { "id": "107", "name": "Reddit", "type": "url", "url": "https://www.reddit.com/" },
            { "id": "108", "name": "Avalanche.org", "type": "url", "url": "https://avalanche.org/" },
            { "id": "109", "name": "Netflix", "type": "url", "url": "https://www.netflix.com/" },
            { "id": "110", "name": "National Park Service", "type": "url", "url": "https://www.nps.gov/" },
            { "id": "111", "name": "Twitch", "type": "url", "url": "https://www.twitch.tv/" },
            { "id": "112", "name": "CalTopo", "type": "url", "url": "https://caltopo.com/" },
            { "id": "113", "name": "Spotify", "type": "url", "url": "https://open.spotify.com/" },
            { "id": "114", "name": "Leave No Trace", "type": "url", "url": "https://lnt.org/" },
            { "id": "115", "name": "X", "type": "url", "url": "https://twitter.com/" },
            { "id": "116", "name": "ArcGIS", "type": "url", "url": "https://www.arcgis.com/" },
            { "id": "117", "name": "Pinterest", "type": "url", "url": "https://www.pinterest.com/" },
            { "id": "118", "name": "Gaia GPS", "type": "url", "url": "https://www.gaiagps.com/" },
            { "id": "119", "name": "Facebook", "type": "url", "url": "https://www.facebook.com/" },
            { "id": "120", "name": "AirNow AQI", "type": "url", "url": "https://www.airnow.gov/" }
         ],
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
      "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
   },
   "version": 1
}
BM_EOF

# 5. Bootstrap Chrome to generate SQLite DBs, then kill it
echo "Bootstrapping Chrome History DB..."
su - ga -c "google-chrome-stable --headless --disable-gpu --dump-dom about:blank > /dev/null 2>&1" || true
sleep 3
pkill -9 -f "google-chrome" || true
sleep 1

# 6. Inject History via Python
python3 << 'PYEOF'
import sqlite3
import time
import os

db_path = '/home/ga/.config/google-chrome/Default/History'
if not os.path.exists(db_path):
    # Create empty DB if Chrome headless didn't
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")
else:
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("CREATE TABLE IF NOT EXISTS urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")

chrome_base = (int(time.time()) + 11644473600) * 1000000

urls = [
    ("https://www.tiktok.com/", "TikTok"),
    ("https://www.recreation.gov/", "Recreation.gov"),
    ("https://www.instagram.com/", "Instagram"),
    ("https://www.weather.gov/", "National Weather Service"),
    ("https://store.steampowered.com/", "Steam"),
    ("https://www.usgs.gov/", "USGS Topo Maps"),
    ("https://www.reddit.com/", "Reddit"),
    ("https://avalanche.org/", "Avalanche.org"),
    ("https://www.netflix.com/", "Netflix"),
    ("https://www.nps.gov/", "National Park Service"),
    ("https://www.twitch.tv/", "Twitch"),
    ("https://caltopo.com/", "CalTopo"),
    ("https://open.spotify.com/", "Spotify"),
    ("https://lnt.org/", "Leave No Trace"),
    ("https://twitter.com/", "X"),
    ("https://www.arcgis.com/", "ArcGIS"),
    ("https://www.pinterest.com/", "Pinterest"),
    ("https://www.gaiagps.com/", "Gaia GPS"),
    ("https://www.facebook.com/", "Facebook"),
    ("https://www.airnow.gov/", "AirNow")
]

for i, (url, title) in enumerate(urls):
    ts = chrome_base - (i * 1000000)
    try:
        c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, 1, 1, ?, 0)", (url, title, ts))
    except sqlite3.OperationalError:
        pass # Ignore if schema mismatch from unexpected Chrome version

conn.commit()
conn.close()
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/.config/google-chrome/

# Start Chrome with CDP
echo "Starting Chrome..."
su - ga -c "/home/ga/launch_chrome.sh about:blank" > /dev/null 2>&1 &
sleep 5

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="