#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Arrangement Conference Workspace Task ==="
date +%s > /tmp/task_start_time.txt

# 1. Prepare Desktop Files
cat > /home/ga/Desktop/arrangement_browser_spec.txt << 'EOF'
ARRANGEMENT CONFERENCE - BROWSER CONFIGURATION STANDARD

This shared display is used to consult with grieving families. Professionalism and privacy are paramount.
Ensure the following before every consultation:

1. BOOKMARKS: 
   - Group resources into exactly 4 folders: "Merchandise", "Cemeteries", "Florists", and "Vital Statistics".
   - Remove ALL personal or non-work bookmarks from the browser immediately.

2. BROWSING HISTORY:
   - Check the recent_families.txt log. Search the browser history for those specific surnames and delete ONLY those entries. 
   - Do NOT clear the entire history (we need to preserve our recent searches for caskets and vendor portals).

3. PRIVACY HARDENING:
   - Disable "Autocomplete searches and URLs" (prevents previous families' names popping up).
   - Disable "Save and fill addresses" and "Save and fill payment methods".

4. DOWNLOADS:
   - Set the default download location to: /home/ga/Documents/Arrangement_Files
   - Turn ON "Ask where to save each file before downloading" (so contracts are explicitly named).

5. SEARCH ENGINE SHORTCUT:
   - Create a site search shortcut with the keyword "obit" pointing to URL: https://www.legacy.com/search?q=%s
EOF

cat > /home/ga/Desktop/recent_families.txt << 'EOF'
RECENT ARRANGEMENT CONFERENCES (Sanitize history for these surnames):
- Patterson
- Smith
- Hernandez
- O'Connor
EOF

mkdir -p /home/ga/Documents/Arrangement_Files
chown -R ga:ga /home/ga/Desktop/ /home/ga/Documents/

# 2. Stop Chrome safely
echo "Stopping Chrome to inject profile data..."
pkill -f "chrome" 2>/dev/null || true
sleep 2

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# 3. Inject Bookmarks (Flat layout - agent must organize)
python3 << 'PYEOF'
import json, os, time

bookmarks = {
   "checksum": "0" * 32,
   "roots": {
      "bookmark_bar": {
         "children": [
            {"name": "Batesville Caskets", "url": "https://www.batesville.com/", "type": "url"},
            {"name": "Netflix", "url": "https://www.netflix.com/", "type": "url"},
            {"name": "Matthews Aurora", "url": "https://www.matthewsaurora.com/", "type": "url"},
            {"name": "Wilbert Vaults", "url": "https://www.wilbert.com/", "type": "url"},
            {"name": "Amazon", "url": "https://www.amazon.com/", "type": "url"},
            {"name": "Messenger Stationery", "url": "https://www.messengerstationery.com/", "type": "url"},
            {"name": "Catholic Cemeteries", "url": "https://www.catholiccemeteries.org/", "type": "url"},
            {"name": "Arlington National", "url": "https://www.arlingtoncemetery.mil/", "type": "url"},
            {"name": "DraftKings", "url": "https://www.draftkings.com/", "type": "url"},
            {"name": "Rose Garden", "url": "https://www.rosegardencemetery.com/", "type": "url"},
            {"name": "Teleflora", "url": "https://www.teleflora.com/", "type": "url"},
            {"name": "Facebook", "url": "https://www.facebook.com/", "type": "url"},
            {"name": "FTD Florists", "url": "https://www.ftd.com/", "type": "url"},
            {"name": "1800Flowers", "url": "https://www.1800flowers.com/", "type": "url"},
            {"name": "Reddit", "url": "https://www.reddit.com/", "type": "url"},
            {"name": "CDC NVSS Vital Stats", "url": "https://www.cdc.gov/nchs/nvss/index.htm", "type": "url"},
            {"name": "TX EDRS Login", "url": "https://txever.dshs.texas.gov/", "type": "url"},
            {"name": "Legacy Obituaries", "url": "https://www.legacy.com/", "type": "url"}
         ],
         "name": "Bookmarks bar", "type": "folder", "id": "1"
      },
      "other": {"children": [], "name": "Other bookmarks", "type": "folder", "id": "2"},
      "synced": {"children": [], "name": "Mobile bookmarks", "type": "folder", "id": "3"}
   },
   "version": 1
}

# Assign IDs and timestamps
base_time = str((int(time.time()) + 11644473600) * 1000000)
for i, child in enumerate(bookmarks["roots"]["bookmark_bar"]["children"]):
    child["id"] = str(i + 4)
    child["date_added"] = base_time
    child["guid"] = f"00000000-0000-4000-a000-{i:012d}"

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

# 4. Generate Chrome History Database
# Chrome requires the DB to be initialized by the browser first for full schema mapping.
# Start headlessly, let it build DB, kill it, then inject.
su - ga -c "google-chrome-stable --headless --disable-gpu --dump-dom https://example.com >/dev/null 2>&1" || true
sleep 3
pkill -f "chrome" 2>/dev/null || true
sleep 1

# Inject History via Python & sqlite3
python3 << 'PYEOF'
import sqlite3, time

db_path = "/home/ga/.config/google-chrome/Default/History"
conn = sqlite3.connect(db_path)
c = conn.cursor()

# Ensure URLs table exists if headless launch failed to create it
c.execute('''CREATE TABLE IF NOT EXISTS urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)''')

base_time = (int(time.time()) + 11644473600) * 1000000

# Insert 30 General history items
general_urls = [
    ("https://www.batesville.com/catalog/caskets", "Batesville Caskets | Catalog"),
    ("https://www.wilbert.com/vaults/standard", "Wilbert Burial Vaults - Standard"),
    ("https://txever.dshs.texas.gov/login", "Texas EDRS - User Login"),
    ("https://www.ftd.com/sympathy-flowers", "Sympathy Flowers & Funeral Arrangements | FTD"),
    ("https://www.cdc.gov/nchs/nvss/deaths.htm", "Mortality Data | NVSS"),
    ("https://www.messengerstationery.com/guestbooks", "Funeral Guestbooks - Messenger"),
]
for i in range(30):
    url, title = general_urls[i % len(general_urls)]
    ts = base_time - (10000000 * i)
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (url, f"{title} (Visit {i})", ts))

# Insert 15 Sensitive history items (The targets to be deleted)
sensitive_data = [
    ("https://txever.dshs.texas.gov/cases/patterson-robert", "EDRS Case - Patterson, Robert"),
    ("https://www.legacy.com/search?name=Patterson", "Obituary Search: Patterson"),
    ("https://www.legacy.com/search?name=Smith", "Obituary Search: Smith"),
    ("https://txever.dshs.texas.gov/cases/smith-mary", "EDRS Case - Smith, Mary"),
    ("https://www.matthewsaurora.com/orders/hernandez-family", "Order Confirmation: Hernandez Family"),
    ("https://www.legacy.com/search?name=Hernandez", "Obituary Search: Hernandez"),
    ("https://www.catholiccemeteries.org/plots/oconnor", "Plot Availability - O'Connor"),
    ("https://txever.dshs.texas.gov/cases/oconnor-william", "EDRS Case - O'Connor, William"),
]
for i in range(15):
    url, title = sensitive_data[i % len(sensitive_data)]
    ts = base_time - (50000000 * i)
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (url, title, ts))

conn.commit()
conn.close()
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome/

# 5. Start Chrome for the Agent
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --window-size=1920,1080 --no-first-run --no-default-browser-check chrome://bookmarks > /dev/null 2>&1 &"
sleep 4

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="