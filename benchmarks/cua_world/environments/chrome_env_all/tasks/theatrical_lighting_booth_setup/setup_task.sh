#!/bin/bash
set -euo pipefail

echo "=== Theatrical Lighting Booth Setup Task ==="
echo "Stopping Chrome to inject test data..."

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Chrome safely
pkill -f "chrome.*remote-debugging-port" || true
sleep 2
pkill -9 -f "google-chrome" || true
sleep 1

# Setup directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/Lighting_Plots"
chown -R ga:ga "/home/ga/Documents/Lighting_Plots"

# Generate 30 flat bookmarks using python for valid JSON
echo "Generating unorganized bookmarks..."
python3 << 'PYEOF'
import json
import time

chrome_base = (int(time.time()) + 11644473600) * 1000000

audio = [("Shure", "shure.com"), ("Yamaha Pro Audio", "yamaha.com"), ("Setlist.fm", "setlist.fm"), ("Ticketmaster", "ticketmaster.com"), ("Spotify", "spotify.com"), ("Soundcloud", "soundcloud.com"), ("ASCAP", "ascap.com"), ("BMI", "bmi.com"), ("Fender", "fender.com"), ("Gibson", "gibson.com")]
fixtures = [("ETC", "etcconnect.com"), ("Chauvet Professional", "chauvetprofessional.com"), ("High End Systems", "highend.com"), ("Vari-Lite", "vari-lite.com"), ("Robe", "robe.cz")]
control = [("MA Lighting", "malighting.com"), ("Obsidian Control", "obsidiancontrol.com"), ("Pathway Connectivity", "pathwayconnect.com"), ("City Theatrical", "citytheatrical.com"), ("Luminex", "luminex.be")]
gels = [("Rosco", "rosco.com"), ("LEE Filters", "leefilters.com"), ("GAM", "gamonline.com"), ("Apollo Design", "apollodesign.net"), ("GoboMan", "goboman.com")]
rigging = [("CM Lodestar", "cm-et.com"), ("Rose City Scale", "rosecityscale.com"), ("USITT", "usitt.org"), ("PLASA", "plasa.org"), ("Actors Equity", "actorsequity.org")]

all_sites = audio + fixtures + control + gels + rigging
children = []

for idx, (name, domain) in enumerate(all_sites):
    children.append({
        "date_added": str(chrome_base - (idx * 600000000)),
        "id": str(idx + 10),
        "name": name,
        "type": "url",
        "url": f"https://www.{domain}/"
    })

bookmarks = {
    "checksum": "00000000000000000000000000000000",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(chrome_base), "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome/

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Capture Initial Screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="