#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up E-Bike Service Terminal task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create required download directory
mkdir -p /home/ga/Documents/Service_Manuals
chown -R ga:ga /home/ga/Documents/Service_Manuals

# Stop Chrome if running to safely modify profile
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# 1. Generate Bookmarks
echo "Creating mixed bookmarks..."
cat > "$CHROME_PROFILE/Bookmarks" << 'EOF'
{
   "checksum": "0",
   "roots": {
      "bookmark_bar": {
         "children": [
            {"id": "1", "name": "Bosch eBike Dealer", "type": "url", "url": "https://www.bosch-ebike.com/us/dealer-portal"},
            {"id": "2", "name": "Pinkbike", "type": "url", "url": "https://www.pinkbike.com/"},
            {"id": "3", "name": "Shimano E-TUBE", "type": "url", "url": "https://e-tubeproject.shimano.com/"},
            {"id": "4", "name": "QBP", "type": "url", "url": "https://www.qbp.com/"},
            {"id": "5", "name": "YouTube", "type": "url", "url": "https://www.youtube.com/"},
            {"id": "6", "name": "Specialized Turbo Tech", "type": "url", "url": "https://www.specialized.com/us/en/turbo"},
            {"id": "7", "name": "DoorDash", "type": "url", "url": "https://www.doordash.com/"},
            {"id": "8", "name": "JBI Bike", "type": "url", "url": "https://www.jbi.bike/site/"},
            {"id": "9", "name": "Shimano Si Manuals", "type": "url", "url": "https://si.shimano.com/"},
            {"id": "10", "name": "Spotify", "type": "url", "url": "https://open.spotify.com/"},
            {"id": "11", "name": "Trek Tech", "type": "url", "url": "https://dex.trekbikes.com/"},
            {"id": "12", "name": "BTI", "type": "url", "url": "https://www.bti-usa.com/"},
            {"id": "13", "name": "SRAM Service", "type": "url", "url": "https://www.sram.com/en/service"},
            {"id": "14", "name": "Park Tool Repair", "type": "url", "url": "https://www.parktool.com/en-us/blog/repair-help"},
            {"id": "15", "name": "Fox Racing Shox", "type": "url", "url": "https://www.ridefox.com/"}
         ],
         "date_added": "13360000000000000",
         "id": "bookmark_bar",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {"children": [], "id": "other", "name": "Other bookmarks", "type": "folder"},
      "synced": {"children": [], "id": "synced", "name": "Mobile bookmarks", "type": "folder"}
   },
   "version": 1
}
EOF

# 2. Generate History and Cookies using Python sqlite3
echo "Generating Chrome History and Cookies..."
python3 << 'PYEOF'
import sqlite3
import time
import os

profile_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_dir, exist_ok=True)

# Generate History
history_db = os.path.join(profile_dir, "History")
conn = sqlite3.connect(history_db)
c = conn.cursor()
c.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL)")

# Chrome timestamps (microseconds since 1601-01-01)
chrome_time = int((time.time() + 11644473600) * 1000000)

domains = [
    ("https://www.youtube.com/watch?v=bike", "MTB Fails"),
    ("https://www.doordash.com/orders", "Lunch Order"),
    ("https://www.pinkbike.com/news", "Pinkbike News"),
    ("https://open.spotify.com/", "Shop Playlist"),
    ("https://www.qbp.com/catalog", "QBP Catalog"),
    ("https://si.shimano.com/manuals", "Shimano Manuals"),
    ("https://www.sram.com/en/service", "SRAM Tech"),
]

for url, title in domains:
    for i in range(3): # Add multiple visits
        c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, ?, ?)", 
                  (f"{url}_{i}", title, 1, chrome_time - (i*1000000)))
conn.commit()
conn.close()

# Generate Cookies
# Network schema for modern Chrome: stored in Network/Cookies
network_dir = os.path.join(profile_dir, "Network")
os.makedirs(network_dir, exist_ok=True)
cookies_db = os.path.join(network_dir, "Cookies")
conn2 = sqlite3.connect(cookies_db)
c2 = conn2.cursor()

# Create standard modern Chrome cookies table
c2.execute("CREATE TABLE cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL, name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB NOT NULL, path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL, samesite INTEGER NOT NULL, source_scheme INTEGER NOT NULL, source_port INTEGER NOT NULL, is_same_party INTEGER NOT NULL, last_update_utc INTEGER NOT NULL, UNIQUE (host_key, top_frame_site_key, name, path))")

cookie_domains = [
    ".youtube.com", ".doordash.com", ".pinkbike.com", ".spotify.com",
    ".qbp.com", "si.shimano.com", ".sram.com"
]

for d in cookie_domains:
    c2.execute("INSERT INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party, last_update_utc) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", 
               (chrome_time, d, "", "session_id", "val", b"enc", "/", chrome_time + 86400000000, 1, 1, chrome_time, 1, 1, 1, -1, 2, 443, 0, chrome_time))
conn2.commit()
conn2.close()

# Also drop a Cookies file in Default just in case (older Chrome versions)
import shutil
shutil.copy2(cookies_db, os.path.join(profile_dir, "Cookies"))
PYEOF

chown -R ga:ga "/home/ga/.config/google-chrome"

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --remote-debugging-port=9222 --restore-last-session > /tmp/chrome.log 2>&1 &"
sleep 5

# Ensure Chrome is maximized
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Provide Instructions
cat > /home/ga/Desktop/shop_terminal_config.txt << 'EOF'
SHOP TERMINAL CONFIGURATION DIRECTIVE
-------------------------------------
Mechanics, please configure this terminal for the service floor:

1. BOOKMARKS: Create 3 folders on the bookmark bar: 'E-Bike Diagnostics', 'B2B Suppliers', and 'Service Manuals'. Move the technical bookmarks into them.
2. CLEANUP: Delete all personal/entertainment bookmarks (YouTube, Pinkbike, DoorDash, Spotify).
3. PRIVACY: Clear history and cookies for the entertainment domains (youtube.com, doordash.com, pinkbike.com, spotify.com). DO NOT wipe everything—we need to stay logged into qbp.com, si.shimano.com, and sram.com!
4. ACCESSIBILITY: Set default font size to 24 and minimum font size to 18 so we can read from the stand.
5. DOWNLOADS: Set the download location to '~/Documents/Service_Manuals' and turn OFF "Ask where to save each file".
6. SEARCH & HOME: Add a custom search engine for Park Tool (Keyword: 'park', URL: 'https://www.parktool.com/en-us/search?q=%s'). Set the homepage to 'https://si.shimano.com'.
EOF
chown ga:ga /home/ga/Desktop/shop_terminal_config.txt

# Final screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "=== Setup complete ==="