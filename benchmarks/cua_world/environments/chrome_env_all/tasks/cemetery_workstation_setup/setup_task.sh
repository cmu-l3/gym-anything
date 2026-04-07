#!/bin/bash
set -euo pipefail

echo "=== Cemetery Workstation Setup Task ==="
echo "Preparing Chrome profile with bookmarks and history..."

# 1. Kill any existing Chrome instances
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true

# 2. Setup directories
mkdir -p /home/ga/.config/google-chrome/Default
mkdir -p /home/ga/Documents/Burial_Records
mkdir -p /home/ga/Desktop

# 3. Create the configuration standard document
cat > /home/ga/Desktop/cemetery_workstation_standard.txt << 'EOF'
Municipal Records Workstation Standard

1. Organize existing work bookmarks into two new folders on the bookmark bar:
   - "Vital Records & Archives"
   - "Grounds & Vendors"
2. Delete ALL personal bookmarks left by the previous manager (ESPN, Amazon, Facebook, YouTube, Zillow, Netflix, DraftKings, Twitter).
3. Configure Chrome to Download PDFs instead of opening them in the browser natively.
4. Set the default download directory to: /home/ga/Documents/Burial_Records
5. Enable "Ask where to save each file before downloading" (critical for filing death certificates).
6. Add two custom search engines (via Manage Search Engines):
   - Keyword: grave  | URL: https://www.findagrave.com/memorial/search?firstname=&lastname=%s
   - Keyword: ssdi   | URL: https://genealogybank.com/explore/ssdi/all?lname=%s
7. Set the startup pages to open exactly these two pages:
   - https://www.findagrave.com
   - https://www.familysearch.org
8. Open Chrome History and delete ONLY the history entries associated with the 8 personal domains listed above. Do not clear the entire history; municipal records history must be preserved.
EOF

# 4. Generate Bookmarks JSON and SQLite History using Python
python3 << 'PYEOF'
import json
import time
import os
import sqlite3
import uuid

CHROME_DIR = "/home/ga/.config/google-chrome/Default"
os.makedirs(CHROME_DIR, exist_ok=True)

vital = [
    ("Find A Grave", "https://www.findagrave.com/"),
    ("FamilySearch", "https://www.familysearch.org/"),
    ("Ancestry", "https://www.ancestry.com/"),
    ("USGenWeb", "https://www.usgenweb.org/"),
    ("National Archives", "https://www.archives.gov/"),
    ("CDC NCHS", "https://www.cdc.gov/nchs/"),
    ("State Dept of Health", "https://www.health.ny.gov/"),
    ("VitalRec", "https://www.vitalrec.com/"),
    ("SSDI", "https://ssdi.rootsweb.com/"),
    ("Interment.net", "https://www.interment.net/"),
    ("BillionGraves", "https://billiongraves.com/"),
    ("Legacy.com", "https://www.legacy.com/")
]

grounds = [
    ("ArcGIS Cemetery Solutions", "https://www.arcgis.com/"),
    ("Graveyard Mapper", "https://www.graveyardmapper.com/"),
    ("John Deere Parts", "https://partscatalog.deere.com/"),
    ("Toro Commercial", "https://www.toro.com/"),
    ("Coldspring USA", "https://www.coldspringusa.com/"),
    ("Matthews Aurora", "https://www.matthewsaurora.com/"),
    ("Batesville Caskets", "https://www.batesville.com/"),
    ("SiteOne Landscaping", "https://www.siteone.com/")
]

personal = [
    ("ESPN", "https://www.espn.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Zillow", "https://www.zillow.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("DraftKings", "https://www.draftkings.com/"),
    ("Twitter", "https://twitter.com/")
]

all_bms = vital + grounds + personal

# Generate Chrome timestamp (microseconds since 1601-01-01)
chrome_base = (int(time.time()) + 11644473600) * 1000000

children = []
bid = 5

for i, (name, url) in enumerate(all_bms):
    children.append({
        "date_added": str(chrome_base - (50 - i) * 600000000),
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": url
    })
    bid += 1

bookmarks = {
    "checksum": "cemetery001",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base - 86400000000),
            "date_modified": str(chrome_base),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(CHROME_DIR, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)

# Generate History DB
history_db_path = os.path.join(CHROME_DIR, "History")
conn = sqlite3.connect(history_db_path)
c = conn.cursor()
c.execute("CREATE TABLE IF NOT EXISTS urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL)")

# Generate some extra work history so total work history is ~40
extra_work = [
    ("https://www.findagrave.com/cemetery/123", "Cemetery 123 - Find A Grave"),
    ("https://www.familysearch.org/search/record/results", "Search Results - FamilySearch"),
    ("https://www.archives.gov/research/genealogy", "Genealogy Research - National Archives"),
    ("https://www.arcgis.com/apps/mapviewer/index.html", "Map Viewer - ArcGIS")
] * 5

# Generate multiple visits for personal to make them visible
personal_visits = [
    ("https://www.espn.com/nfl", "NFL Football - ESPN"),
    ("https://www.amazon.com/orders", "Your Orders - Amazon"),
    ("https://www.facebook.com/messages", "Messages - Facebook"),
    ("https://www.youtube.com/watch?v=123", "Funny Video - YouTube"),
    ("https://www.zillow.com/homes", "Real Estate - Zillow"),
    ("https://www.netflix.com/browse", "Browse - Netflix"),
    ("https://www.draftkings.com/lobby", "Lobby - DraftKings"),
    ("https://twitter.com/home", "Home - Twitter")
] * 3

history_entries = all_bms + extra_work + personal_visits

for idx, (title, url) in enumerate(history_entries):
    # If the tuple came from all_bms it is (name, url), else (url, title)
    if not url.startswith("http"):
        url, title = title, url # swap if needed
        
    visit_time = chrome_base - (100 - idx) * 3600000000
    c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time) VALUES (?, ?, ?, ?, ?)", 
              (url, title, 1, 0, visit_time))

conn.commit()
conn.close()
PYEOF

# Ensure permissions
chown -R ga:ga /home/ga/.config/google-chrome
chown -R ga:ga /home/ga/Documents/Burial_Records
chown ga:ga /home/ga/Desktop/cemetery_workstation_standard.txt

# 5. Start Chrome
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check &"
sleep 5

# 6. Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="