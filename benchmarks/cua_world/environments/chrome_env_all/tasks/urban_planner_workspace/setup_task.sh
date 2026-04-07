#!/usr/bin/env bash
set -euo pipefail

echo "=== Municipal Urban Planner Workspace Task Setup ==="
echo "Task: Configure Chrome for urban planning workflows and presentations"

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Stop Chrome if running to safely prepare profile data
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# Create expected directories
mkdir -p /home/ga/Documents/Spatial_Data
chown -R ga:ga /home/ga/Documents/Spatial_Data

# 1. Create the Specification Document
cat > /home/ga/Desktop/planning_browser_spec.txt << 'EOF'
MUNICIPAL PLANNING BROWSER CONFIGURATION STANDARD

To prepare this workstation for public City Council presentations and daily GIS tasks, implement the following changes:

1. BOOKMARK ORGANIZATION
Create the following 5 folders on the Bookmark Bar and move the appropriate professional bookmarks into them:
- "GIS & Maps": HUD eGIS, FEMA, OpenStreetMap, Google Earth, EPA EJScreen
- "Demographics": Census, BLS, BEA
- "Zoning & Code": Municode, American Planning Assoc, Int'l Code Council
- "Transportation": NACTO, FTA, FHWA, MUTCD, Strong Towns
- "Public Engagement": Nextdoor, Polco, PublicInput, Planetizen

2. BROWSER SANITIZATION (CRITICAL FOR PUBLIC PRESENTATIONS)
- Delete ALL 15 personal/entertainment bookmarks from the browser (Netflix, Reddit, Spotify, Tinder, etc.)
- Delete ALL Browsing History entries associated with those 15 personal domains to prevent autocomplete during live screen-sharing.
- Clear ALL Cookies associated with those 15 personal domains.
- DO NOT delete history or cookies for the professional planning websites.

3. ACCESSIBILITY & PRESENTATION
- Change the Default Font Size to 18 (so text is readable on the projector).

4. CUSTOM SEARCH SHORTCUTS
- Create a site search shortcut with keyword 'municode'
- Create a site search shortcut with keyword 'parcel'

5. DOWNLOAD MANAGEMENT
- Change default download location to: /home/ga/Documents/Spatial_Data
- Turn ON "Ask where to save each file before downloading" (needed for organizing shapefiles)

6. STARTUP PAGES
- Configure Chrome to open a specific set of pages on startup:
  1. data.census.gov
  2. ejscreen.epa.gov/mapper
EOF
chown ga:ga /home/ga/Desktop/planning_browser_spec.txt

# 2. Inject Bookmarks, History, and Cookies using Python
echo "Injecting Chrome data (Bookmarks, History, Cookies)..."

python3 << 'PYEOF'
import json, time, sqlite3, os

chrome_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(chrome_dir, exist_ok=True)

pro_domains = {
    "HUD eGIS": "egis.hud.gov", "FEMA Flood Maps": "msc.fema.gov", "OpenStreetMap": "openstreetmap.org",
    "Google Earth": "earth.google.com", "EPA EJScreen": "ejscreen.epa.gov/mapper",
    "Census Data": "data.census.gov", "BLS": "bls.gov", "BEA": "bea.gov", 
    "Municode": "library.municode.com", "American Planning Assoc": "planning.org", 
    "Int'l Code Council": "iccsafe.org", "NACTO": "nacto.org", "FTA": "transit.dot.gov", 
    "FHWA": "fhwa.dot.gov", "MUTCD": "mutcd.fhwa.dot.gov", "Strong Towns": "strongtowns.org",
    "Nextdoor": "nextdoor.com", "Polco": "polco.us", "PublicInput": "publicinput.com", 
    "Planetizen": "planetizen.com"
}

personal_domains = {
    "Netflix": "netflix.com", "Reddit": "reddit.com", "X": "x.com", "Hulu": "hulu.com", 
    "Steam": "steampowered.com", "Twitch": "twitch.tv", "Facebook": "facebook.com", 
    "Instagram": "instagram.com", "TikTok": "tiktok.com", "ESPN": "espn.com", 
    "DraftKings": "draftkings.com", "Pinterest": "pinterest.com", "Etsy": "etsy.com", 
    "Spotify": "spotify.com", "Tinder": "tinder.com"
}

all_sites = {**pro_domains, **personal_domains}

# 1. Bookmarks JSON
children = []
bid = 5
for name, domain in all_sites.items():
    children.append({
        "date_added": "13360000000000000",
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": f"https://{domain}/"
    })
    bid += 1

bookmarks_data = {
    "checksum": "0",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": "13360000000000000", "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": "13360000000000000", "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": "13360000000000000", "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(f"{chrome_dir}/Bookmarks", "w") as f:
    json.dump(bookmarks_data, f, indent=3)

# 2. History SQLite
hist_db = f"{chrome_dir}/History"
conn = sqlite3.connect(hist_db)
c = conn.cursor()
c.execute("CREATE TABLE IF NOT EXISTS urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0);")
c.execute("CREATE TABLE IF NOT EXISTS visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0, segment_id INTEGER, visit_duration INTEGER DEFAULT 0, incremented_omnibox_typed_score BOOLEAN DEFAULT FALSE);")

current_time = int(time.time() * 1000000)
for idx, (name, domain) in enumerate(all_sites.items()):
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, ?, ?)", 
              (f"https://{domain}/", name, 5, current_time - (idx * 10000)))
conn.commit()
conn.close()

# 3. Cookies SQLite
cookies_db = f"{chrome_dir}/Cookies"
conn = sqlite3.connect(cookies_db)
c = conn.cursor()
c.execute("CREATE TABLE IF NOT EXISTS cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, top_frame_site_key TEXT NOT NULL DEFAULT '', name TEXT NOT NULL, value TEXT NOT NULL, encrypted_value BLOB DEFAULT '', path TEXT NOT NULL, expires_utc INTEGER NOT NULL, is_secure INTEGER NOT NULL, is_httponly INTEGER NOT NULL, last_access_utc INTEGER NOT NULL, has_expires INTEGER NOT NULL, is_persistent INTEGER NOT NULL, priority INTEGER NOT NULL DEFAULT 1, samesite INTEGER NOT NULL DEFAULT -1, source_scheme INTEGER NOT NULL DEFAULT 0, source_port INTEGER NOT NULL DEFAULT -1, is_same_party INTEGER NOT NULL DEFAULT 0, last_update_utc INTEGER NOT NULL DEFAULT 0);")

for idx, domain in enumerate(all_sites.values()):
    c.execute("INSERT INTO cookies (creation_utc, host_key, name, value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
              (current_time, f".{domain}", "session_id", "test_value_123", "/", current_time + 10000000, 1, 1, current_time, 1, 1))
conn.commit()
conn.close()

# Ensure file ownership
os.system(f"chown -R ga:ga {chrome_dir}")
PYEOF

echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="