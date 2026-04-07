#!/bin/bash
set -euo pipefail

echo "=== QA Shopfloor Terminal Task Setup ==="
echo "Task: Configure shared QA terminal for accessibility and privacy per SOP"

# 1. Kill any running Chrome to safely modify profile data
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# 2. Prepare Chrome profile directory and Download directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/CMM_Reports"
chown -R ga:ga "/home/ga/.config/google-chrome"
chown -R ga:ga "/home/ga/Documents/CMM_Reports"

# 3. Create SOP Document
cat > "/home/ga/Desktop/QA_Terminal_SOP.txt" << 'EOF'
======================================================
QA TERMINAL - STANDARD OPERATING PROCEDURE (SOP)
======================================================

1. UNAUTHORIZED SITES
   Delete all personal bookmarks from the browser (ESPN, Netflix, Facebook, Twitter, Amazon, YouTube).

2. BOOKMARK ORGANIZATION
   Create these 4 folders on the bookmark bar and categorize the remaining sites:
   - "Metrology" (Mitutoyo, Zeiss, Hexagon, Renishaw, Keyence)
   - "SPC Dashboards" (InfinityQS, WinSPC, Plex, Tulip)
   - "ISO & Standards" (ISO, ASTM, ASQ, NIST)
   - "Tooling" (Sandvik, Kennametal, Haas)

3. ACCESSIBILITY (For operators with safety glasses)
   - Default font size: 22
   - Fixed-width font: 20
   - Minimum font size: 16
   - Enable "Force Dark Mode for Web Contents" in chrome://flags to reduce glare.

4. PRIVACY (Shared Shift Terminal)
   - Cookies: Set to clear cookies and site data when you close all windows.
   - Passwords: Turn OFF saving passwords.

5. PRODUCTIVITY
   - Create a site search shortcut. Keyword: "mcmaster" URL: "https://www.mcmaster.com/find/%s"
   - Downloads: Set default location to /home/ga/Documents/CMM_Reports
   - Enable "Ask where to save each file before downloading"
EOF
chown ga:ga "/home/ga/Desktop/QA_Terminal_SOP.txt"

# 4. Generate Bookmarks JSON using Python
echo "Generating flat bookmarks..."
python3 << 'PYEOF'
import json
import time
import uuid

# Base timestamp (Chrome format: microseconds since 1601)
base_time = (int(time.time()) + 11644473600) * 1000000

sites = [
    ("Mitutoyo Metrology", "https://www.mitutoyo.com"),
    ("ESPN Sports", "https://www.espn.com"),
    ("Zeiss Industrial", "https://www.zeiss.com/metrology"),
    ("Netflix", "https://www.netflix.com"),
    ("Hexagon MI", "https://www.hexagonmi.com"),
    ("Renishaw CMM", "https://www.renishaw.com"),
    ("Facebook", "https://www.facebook.com"),
    ("Keyence", "https://www.keyence.com"),
    ("InfinityQS", "https://www.infinityqs.com"),
    ("Twitter", "https://twitter.com"),
    ("WinSPC", "https://www.winspc.com"),
    ("Amazon", "https://www.amazon.com"),
    ("Plex Smart Mfg", "https://www.plex.com"),
    ("Tulip Interfaces", "https://tulip.co"),
    ("YouTube", "https://www.youtube.com"),
    ("ISO 9001", "https://www.iso.org"),
    ("ASTM International", "https://www.astm.org"),
    ("ASQ", "https://asq.org"),
    ("NIST Calibrations", "https://www.nist.gov"),
    ("Sandvik Coromant", "https://www.sandvik.coromant.com"),
    ("Kennametal", "https://www.kennametal.com"),
    ("Haas Automation", "https://www.haascnc.com")
]

children = []
for i, (name, url) in enumerate(sites):
    children.append({
        "date_added": str(base_time - (i * 600000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "qa_terminal_init",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(base_time),
            "date_modified": str(base_time),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": str(base_time),
            "date_modified": "0",
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": str(base_time),
            "date_modified": "0",
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "/home/ga/.config/google-chrome/Default/Bookmarks"

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable > /tmp/chrome.log 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="