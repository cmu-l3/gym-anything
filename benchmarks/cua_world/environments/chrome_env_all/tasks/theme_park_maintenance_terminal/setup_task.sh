#!/bin/bash
set -euo pipefail

echo "=== Setting up Theme Park Maintenance Terminal Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop any running Chrome instances
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Set up Chrome CDP profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"

# 1. Create Bookmarks (Flat layout with technical and non-work domains)
echo "Generating Bookmarks..."
cat > /tmp/init_bookmarks.py << 'PYEOF'
import json, uuid, time, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

tech_urls = [
    ("ASTM F2291", "https://www.astm.org/f2291-23.html"),
    ("Rockwell Automation", "https://www.rockwellautomation.com/"),
    ("Siemens", "https://www.siemens.com/"),
    ("OSHA Amusement Parks", "https://www.osha.gov/amusement-parks"),
    ("SaferParks", "https://saferparks.org/"),
    ("NAARSO", "https://naarso.com/"),
    ("McMaster-Carr", "https://www.mcmaster.com/"),
    ("Grainger", "https://www.grainger.com/"),
    ("Fastenal", "https://www.fastenal.com/"),
    ("Motion Industries", "https://www.motionindustries.com/"),
    ("National Weather Service", "https://www.weather.gov/"),
    ("Weather Radar", "https://radar.weather.gov/"),
    ("Lightning Maps", "https://www.lightningmaps.org/"),
    ("MesoWest", "https://mesowest.utah.edu/"),
    ("IAAPA", "https://www.iaapa.org/"),
    ("NFPA Catalog", "https://www.nfpacatalog.org/"),
    ("SKF Support", "https://www.skf.com/group/support"),
    ("Fluke Manuals", "https://www.fluke.com/en-us/support/manuals"),
    ("WAGO", "https://www.wago.com/"),
    ("Schneider Electric", "https://www.schneider-electric.us/")
]

nonwork_urls = [
    ("YouTube", "https://www.youtube.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("X (Twitter)", "https://x.com/"),
    ("TikTok", "https://www.tiktok.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("Hulu", "https://www.hulu.com/"),
    ("Disney+", "https://www.disneyplus.com/"),
    ("Bleacher Report", "https://bleacherreport.com/")
]

children = []
bid = 5

for name, url in tech_urls + nonwork_urls:
    children.append({
        "date_added": str(chrome_base - bid * 10000000),
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
            "date_added": "13360000000000000",
            "date_modified": "13360000000000000",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": "13360000000000000",
            "date_modified": "13360000000000000",
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": "13360000000000000",
            "date_modified": "13360000000000000",
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome-cdp/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
python3 /tmp/init_bookmarks.py

# 2. Create History DB
echo "Generating History database..."
cat > /tmp/init_history.py << 'PYEOF'
import sqlite3, time, os

db_path = "/home/ga/.config/google-chrome-cdp/Default/History"
if not os.path.exists(os.path.dirname(db_path)):
    os.makedirs(os.path.dirname(db_path))

conn = sqlite3.connect(db_path)
c = conn.cursor()

c.execute("CREATE TABLE IF NOT EXISTS urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL)")
c.execute("CREATE TABLE IF NOT EXISTS visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0 NOT NULL, segment_id INTEGER, visit_duration INTEGER DEFAULT 0 NOT NULL, incremented_omnibox_typed_score INTEGER DEFAULT 0 NOT NULL)")

chrome_base = (int(time.time()) + 11644473600) * 1000000

urls = [
    "https://www.astm.org/f2291-23.html", "https://www.rockwellautomation.com/", "https://www.siemens.com/", 
    "https://www.osha.gov/amusement-parks", "https://saferparks.org/", "https://naarso.com/", "https://www.mcmaster.com/",
    "https://www.grainger.com/", "https://www.fastenal.com/", "https://www.motionindustries.com/", "https://www.weather.gov/",
    "https://radar.weather.gov/", "https://www.lightningmaps.org/", "https://mesowest.utah.edu/", "https://www.iaapa.org/",
    "https://www.nfpacatalog.org/", "https://www.skf.com/group/support", "https://www.fluke.com/en-us/support/manuals",
    "https://www.wago.com/", "https://www.schneider-electric.us/",
    "https://www.youtube.com/watch?v=123", "https://www.espn.com/nfl", "https://www.reddit.com/r/funny", 
    "https://www.netflix.com/browse", "https://x.com/home", "https://www.tiktok.com/foryou", "https://www.instagram.com/",
    "https://www.hulu.com/", "https://www.disneyplus.com/", "https://bleacherreport.com/"
]

for i, url in enumerate(urls):
    ts = chrome_base - (i * 10000000)
    c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, 1, 0, ?, 0)", (url, "Title", ts))
    uid = c.lastrowid
    c.execute("INSERT INTO visits (url, visit_time, transition) VALUES (?, ?, 0)", (uid, ts))

conn.commit()
conn.close()
PYEOF
python3 /tmp/init_history.py

# Fix permissions
chown -R ga:ga /home/ga/.config/google-chrome-cdp

# 3. Create spec document
echo "Creating spec document..."
cat > /home/ga/Desktop/morning_shift_config.txt << 'EOF'
Apex Dive - Maintenance Bay Terminal Configuration
Morning Inspection Shift

1. BOOKMARKS
Delete all entertainment and social media bookmarks. Organize the remaining technical bookmarks into the following 4 folders exactly:
- "Schematics & Manuals" (ASTM, Rockwell, Siemens, NFPA, SKF, Fluke, Wago, Schneider)
- "Safety & Logs" (OSHA, SaferParks, NAARSO, IAAPA)
- "Part Suppliers" (McMaster-Carr, Grainger, Fastenal, Motion Industries)
- "Sensors & Weather" (Weather.gov, Radar, LightningMaps, MesoWest)

2. BROWSING HISTORY
The overnight crew visited several entertainment sites (YouTube, Netflix, ESPN, Reddit, etc.). Delete all history entries for these non-work domains.
CRITICAL: Do NOT "Clear All" history. You must preserve the history for our technical domains (manuals and suppliers), as we need those logs for audit traceability.

3. DISPLAY SETTINGS
The tablet is mounted on a gantry. Go to Chrome Settings -> Appearance -> Customize fonts, and set the "Font size" (base font size) to exactly 24.

4. SEARCH ENGINE
Add a custom site search shortcut for rapid part lookup:
- Search engine name: Grainger Parts
- Shortcut keyword: part
- URL with %s in place of query: https://www.grainger.com/search?searchQuery=%s

5. STARTUP PAGES
Configure Chrome to "Open a specific page or set of pages" on startup. Add exactly these two URLs:
- https://radar.weather.gov/
- https://www.osha.gov/amusement-parks
EOF
chown ga:ga /home/ga/Desktop/morning_shift_config.txt

# 4. Launch Chrome CDP profile
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank > /dev/null 2>&1 &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="