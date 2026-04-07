#!/bin/bash
set -euo pipefail

echo "=== Setting up Gemology Lab Workspace Task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Stop Chrome if running to safely modify profile
pkill -f "chrome" 2>/dev/null || true
sleep 2

# Ensure required directories exist
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

DOWNLOAD_DIR="/home/ga/Documents/Appraisal_Reports"
mkdir -p "$DOWNLOAD_DIR"
chown -R ga:ga "$DOWNLOAD_DIR"

# Write the specification file to Desktop
cat > /home/ga/Desktop/lab_browser_spec.txt << 'EOF'
GEMOLOGY LABORATORY - WORKSTATION BROWSER SPECIFICATION v2.1

1. BOOKMARK ORGANIZATION
   Create the following folders on the Bookmark Bar and sort the existing professional links into them:
   - "Grading & Labs" (GIA, AGS, IGI, Gem-A, SSEF)
   - "Market Data" (Rapaport, Polygons, Kitco, JCK)
   - "Compliance" (Kimberley Process, RJC, FTC)
   - "Lab Equipment" (GemOro, Presidium, Leica, Mettler-Toledo)

2. DATA HYGIENE
   The IT technician left personal bookmarks on this machine.
   - Delete all personal/shopping bookmarks (Amazon, Netflix, Reddit, ESPN, Zappos)
   - Delete all corresponding visits to these personal sites from the Chrome Browsing History.
   - Do NOT delete the professional lab history.

3. VISUAL ACCESSIBILITY
   To ensure readability from across the workbench while handling assets:
   - Set Chrome's default font size to 20 (Large/Very Large).

4. DOWNLOADS & SECURITY
   - Set the default download location to: /home/ga/Documents/Appraisal_Reports
   - Turn ON "Ask where to save each file before downloading".
   - Block third-party cookies in Privacy and Security settings.
EOF
chown ga:ga /home/ga/Desktop/lab_browser_spec.txt

# Create Bookmarks and History using a Python script for well-formed data
python3 << 'PYEOF'
import json
import sqlite3
import time
import os
import uuid

chrome_profile = "/home/ga/.config/google-chrome/Default"
chrome_base_time = int((time.time() + 11644473600) * 1000000)

prof_sites = [
    ("https://www.gia.edu/", "GIA - Gemological Institute of America"),
    ("https://www.ags.org/", "American Gem Society"),
    ("https://www.igi.org/", "International Gemological Institute"),
    ("https://gem-a.com/", "Gem-A"),
    ("https://www.ssef.ch/", "SSEF Swiss Gemmological Institute"),
    ("https://www.rapaport.com/", "Rapaport Diamond Prices"),
    ("https://www.polygons.net/", "Polygons Gem Network"),
    ("https://www.kitco.com/", "Kitco Precious Metals"),
    ("https://www.jckonline.com/", "JCK Magazine"),
    ("https://www.kimberleyprocess.com/", "Kimberley Process"),
    ("https://www.responsiblejewellery.com/", "Responsible Jewellery Council"),
    ("https://www.ftc.gov/", "Federal Trade Commission"),
    ("https://www.gemoro.com/", "GemOro Superior Instruments"),
    ("https://www.presidium.com.sg/", "Presidium Instruments"),
    ("https://www.leica-microsystems.com/", "Leica Microscopes"),
    ("https://www.mettler-toledo.com/", "Mettler Toledo Scales")
]

personal_sites = [
    ("https://www.amazon.com/", "Amazon"),
    ("https://www.netflix.com/", "Netflix"),
    ("https://www.reddit.com/", "Reddit"),
    ("https://www.espn.com/", "ESPN"),
    ("https://www.zappos.com/", "Zappos")
]

all_sites = prof_sites + personal_sites

# 1. GENERATE BOOKMARKS JSON
children = []
for i, (url, title) in enumerate(all_sites):
    children.append({
        "date_added": str(chrome_base_time - (i * 1000000)),
        "guid": str(uuid.uuid4()),
        "id": str(5 + i),
        "name": title,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base_time),
            "date_modified": str(chrome_base_time),
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
    json.dump(bookmarks, f)

# 2. GENERATE HISTORY SQLITE
db_path = os.path.join(chrome_profile, "History")
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute("CREATE TABLE urls (id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")
c.execute("CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0, segment_id INTEGER, visit_duration INTEGER DEFAULT 0, incremented_omnibox_typed_score BOOLEAN DEFAULT FALSE)")

for url, title in all_sites:
    vt = chrome_base_time - 3600000000  # 1 hour ago
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (url, title, vt))
    
conn.commit()
conn.close()
PYEOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
chown ga:ga "$CHROME_PROFILE/History"

# Start Chrome in the background
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="