#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Avalanche Dispatch Browser task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure target download directory exists
mkdir -p /home/ga/Documents/Incident_Reports
chown -R ga:ga /home/ga/Documents

# 1. Stop Chrome to safely configure the profile
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
pkill -f "chromium" 2>/dev/null || true
sleep 2

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome

# 2. Generate Initial Preferences (bad defaults to be fixed)
echo "Generating default Preferences..."
python3 << 'PYEOF'
import json, os
prefs = {
    "profile": {
        "password_manager_enabled": True,
        "default_content_setting_values": {"cookies": 1}
    },
    "autofill": {
        "profile_enabled": True,
        "credit_card_enabled": True
    },
    "session": {
        "restore_on_startup": 5
    },
    "download": {
        "default_directory": "/home/ga/Downloads",
        "prompt_for_download": False
    }
}
os.makedirs('/home/ga/.config/google-chrome/Default', exist_ok=True)
with open('/home/ga/.config/google-chrome/Default/Preferences', 'w') as f:
    json.dump(prefs, f)
PYEOF

# 3. Generate Flat Bookmarks List
echo "Generating initial flat bookmarks..."
python3 << 'PYEOF'
import json, time, uuid

chrome_base = (int(time.time()) + 11644473600) * 1000000

# Tuples of (URL, Name)
bookmarks_list = [
    # Avalanche & Weather
    ("https://avalanche.org", "Avalanche.org"),
    ("https://avalanche.state.co.us", "CAIC"),
    ("https://nwac.us", "NWAC"),
    ("https://mesowest.utah.edu", "MesoWest"),
    ("https://www.wpc.ncep.noaa.gov", "WPC NOAA"),
    ("https://www.weather.gov", "NWS Weather"),
    ("https://snodas.noaa.gov", "SNODAS"),
    ("https://www.nrcs.usda.gov/snotel", "SNOTEL"),
    # Medical Protocols
    ("https://wemjournal.org", "Wilderness Medicine"),
    ("https://nremt.org", "NREMT"),
    ("https://redcross.org", "Red Cross"),
    ("https://heart.org", "AHA"),
    ("https://pubmed.ncbi.nlm.nih.gov", "PubMed"),
    ("https://cdc.gov/niosh", "NIOSH"),
    # Operations
    ("https://fcc.gov/uls", "FCC Radio Licensing"),
    ("https://dol.gov/agencies/osha", "OSHA"),
    ("https://fs.usda.gov", "Forest Service"),
    ("https://faa.gov/uas", "FAA Drones"),
    ("https://americanavalancheassociation.org", "A3"),
    ("https://nsp.org", "National Ski Patrol"),
    # Off-Duty Media
    ("https://tetongravity.com", "TGR"),
    ("https://newschoolers.com", "Newschoolers"),
    ("https://powder.com", "Powder Mag"),
    ("https://outsideonline.com", "Outside"),
    ("https://youtube.com", "YouTube"),
    ("https://netflix.com", "Netflix"),
    ("https://spotify.com", "Spotify"),
    ("https://instagram.com", "Instagram"),
    ("https://reddit.com/r/skiing", "r/skiing"),
    ("https://backcountry.com", "Backcountry Gear")
]

children = []
bid = 5
for i, (url, name) in enumerate(bookmarks_list):
    children.append({
        "date_added": str(chrome_base - i * 1000000),
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
            "date_added": str(chrome_base),
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

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome

# 4. Write Specification Document
cat > /home/ga/Desktop/dispatch_terminal_spec.txt << 'EOF'
=== SKI PATROL DISPATCH TERMINAL STANDARD ===

1. BOOKMARK ORGANIZATION
Create four folders on the bookmark bar and sort the existing loose bookmarks into them:
- "Avalanche & Weather" (for forecasting tools: avalanche.org, CAIC, NWAC, MesoWest, WPC, Weather.gov, SNODAS, SNOTEL)
- "Medical Protocols" (for WEM, NREMT, Red Cross, AHA, PubMed, NIOSH)
- "Operations" (for FCC, OSHA, Forest Service, FAA, A3, NSP)
- "Off-Duty Media" (quarantine all distracting sites here: TGR, Newschoolers, YouTube, Netflix, Spotify, Reddit, etc.)

2. STARTUP SEQUENCE
Configure Chrome to "Open a specific page or set of pages" on startup. Add exactly these three URLs:
- https://avalanche.org
- https://mesowest.utah.edu
- https://www.weather.gov

3. PRIVACY & CACHING (CRITICAL FOR LIVE TELEMETRY)
Ensure the browser clears all cookies and site data when you close all windows. Stale cached weather data can be dangerous.
Disable all Password saving and Address/Payment Autofill.

4. DOWNLOADS
Set the default download location to: /home/ga/Documents/Incident_Reports
EOF
chown ga:ga /home/ga/Desktop/dispatch_terminal_spec.txt

# 5. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --window-size=1920,1080 > /tmp/chrome.log 2>&1 &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="