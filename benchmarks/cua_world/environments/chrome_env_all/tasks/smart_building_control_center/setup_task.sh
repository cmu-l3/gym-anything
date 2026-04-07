#!/usr/bin/env bash
set -e

echo "=== Setting up Smart Building Control Center Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop Chrome if running to modify profile safely
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# ============================================================
# Create the Control Room SOP Document
# ============================================================
cat > /home/ga/Desktop/control_room_SOP.txt << 'EOF'
SMART BUILDING CONTROL CENTER - BROWSER SOP
===========================================

The previous shift left the control room browser in an unacceptable state. 
Please reconfigure the Chrome browser immediately before the morning operations begin.

1. BOOKMARK ORGANIZATION
   Organize the existing work bookmarks on the bookmark bar into exactly four folders:
   - "HVAC" (Siemens, Johnson Controls, Trane, Honeywell)
   - "Security" (Avigilon, Genetec, HID Global)
   - "Lighting" (Lutron, Schneider Electric, Cree Lighting)
   - "Parts" (Grainger, McMaster-Carr, Fastenal, HD Supply)

2. SECURITY & SANITIZATION
   - Delete ALL personal and entertainment bookmarks (Netflix, Reddit, ESPN, etc.).
   - Open Chrome History and SURGICALLY DELETE all visits to personal/entertainment sites. 
     DO NOT use "Clear browsing data" for all time, as we MUST PRESERVE the operational 
     work history logs (visits to Siemens, Trane, etc. must remain).
   - Go to Chrome Settings and completely DISABLE the Password Manager ("Offer to save passwords").
     This is a shared terminal; credentials must not be saved.

3. WORKFLOW EFFICIENCY
   - Create a Custom Search Engine:
     * Name: McMaster-Carr
     * Shortcut/Keyword: mcm
     * URL: https://www.mcmaster.com/search?s=%s
   - Create a Desktop Shortcut:
     * We need instant access to Grainger.
     * Create a shortcut on the Linux Desktop named "Grainger" that points to https://www.grainger.com/

Thank you,
Chief Building Engineer
EOF
chown ga:ga /home/ga/Desktop/control_room_SOP.txt

# ============================================================
# Initialize Profile, Bookmarks, and History Databases
# ============================================================
echo "Initializing Chrome Profile Data via Python..."

python3 << 'PYEOF'
import json
import sqlite3
import time
import os
import uuid

chrome_profile = "/home/ga/.config/google-chrome/Default"
os.makedirs(chrome_profile, exist_ok=True)

# 1. BOOKMARKS
work_bms = [
    ("Siemens Building Tech", "https://www.siemens.com/global/en/products/buildings.html"),
    ("Johnson Controls Metasys", "https://www.johnsoncontrols.com/"),
    ("Trane Commercial", "https://www.trane.com/commercial/north-america/us/en.html"),
    ("Honeywell Forge", "https://www.honeywell.com/us/en"),
    ("Avigilon Control Center", "https://www.avigilon.com/"),
    ("Genetec Security Center", "https://www.genetec.com/"),
    ("HID Global Origo", "https://www.hidglobal.com/"),
    ("Lutron Quantum", "https://www.lutron.com/"),
    ("Schneider Electric EcoStruxure", "https://www.se.com/us/en/"),
    ("Cree Lighting SmartCast", "https://www.creelighting.com/"),
    ("Grainger Industrial", "https://www.grainger.com/"),
    ("McMaster-Carr", "https://www.mcmaster.com/"),
    ("Fastenal", "https://www.fastenal.com/"),
    ("HD Supply", "https://hdsupplysolutions.com/")
]

personal_bms = [
    ("Netflix", "https://www.netflix.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Twitter", "https://twitter.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("TikTok", "https://www.tiktok.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Hulu", "https://www.hulu.com/"),
    ("Spotify", "https://open.spotify.com/"),
    ("Twitch", "https://www.twitch.tv/")
]

# Mix them up so they are unorganized
all_bms = work_bms[:7] + personal_bms[:5] + work_bms[7:] + personal_bms[5:]
chrome_base_time = str((int(time.time()) + 11644473600) * 1000000)

children = []
for i, (name, url) in enumerate(all_bms):
    children.append({
        "date_added": chrome_base_time,
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_obj = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": chrome_base_time,
            "date_modified": chrome_base_time,
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(chrome_profile, "Bookmarks"), "w") as f:
    json.dump(bookmarks_obj, f)

# 2. HISTORY
history_db_path = os.path.join(chrome_profile, "History")
# If it exists from a previous run, remove it to ensure clean state
if os.path.exists(history_db_path):
    os.remove(history_db_path)

conn = sqlite3.connect(history_db_path)
c = conn.cursor()
c.execute("CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0 NOT NULL, typed_count INTEGER DEFAULT 0 NOT NULL, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0 NOT NULL);")
c.execute("CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0 NOT NULL, segment_id INTEGER, visit_duration INTEGER DEFAULT 0 NOT NULL, incremented_omnibox_typed_score BOOLEAN DEFAULT FALSE NOT NULL);")

base_ts = (int(time.time()) + 11644473600) * 1000000

# Insert Work History (25 entries)
for i in range(25):
    bm = work_bms[i % len(work_bms)]
    ts = base_ts - (1000000 * 3600 * 24) + (i * 1000000 * 60) # Over the last day
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (bm[1], bm[0], ts))
    url_id = c.lastrowid
    c.execute("INSERT INTO visits (url, visit_time) VALUES (?, ?)", (url_id, ts))

# Insert Personal History (15 entries)
for i in range(15):
    bm = personal_bms[i % len(personal_bms)]
    ts = base_ts - (1000000 * 3600 * 5) + (i * 1000000 * 180) # Over the last 5 hours
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (bm[1], bm[0], ts))
    url_id = c.lastrowid
    c.execute("INSERT INTO visits (url, visit_time) VALUES (?, ?)", (url_id, ts))

conn.commit()
conn.close()

# 3. PREFERENCES
prefs_path = os.path.join(chrome_profile, "Preferences")
prefs = {
    "profile": {
        "password_manager_enabled": True
    },
    "credentials_enable_service": True,
    "browser": {
        "show_home_button": True
    }
}
with open(prefs_path, "w") as f:
    json.dump(prefs, f)

PYEOF

chown -R ga:ga "$CHROME_PROFILE"

# ============================================================
# Launch Chrome & Record Initial State
# ============================================================
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank &"
sleep 5

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Give time for the UI to stabilize
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="