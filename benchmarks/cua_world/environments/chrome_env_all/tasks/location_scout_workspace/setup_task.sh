#!/usr/bin/env bash
set -euo pipefail

echo "=== Location Scout Workspace Task Setup ==="
echo "Task: Configure browser for Desert Mirage production logistics"

# 1. Kill any running Chrome to safely modify profile data
echo "Stopping Chrome to inject test data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chromium" 2>/dev/null || true
sleep 2

# 2. Prepare Chrome profile directory and Target Directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
TARGET_DIR="/home/ga/Documents/Desert_Mirage_Production"
mkdir -p "$TARGET_DIR"
chown -R ga:ga /home/ga/.config/google-chrome/
chown -R ga:ga "$TARGET_DIR"

# 3. Create the Spec File
SPEC_FILE="/home/ga/Desktop/desert_mirage_browser_spec.txt"
cat > "$SPEC_FILE" << 'EOF'
DESERT MIRAGE - PRODUCTION BINDER BROWSER SPECIFICATION
-------------------------------------------------------

We are shooting in New Mexico. The previous Georgia shoot bookmarks are still here. Clean this up.

1. BOOKMARKS CLEANUP & ORGANIZATION:
   - DELETE all bookmarks related to the Georgia shoot (georgia.org, atlantaga.gov).
   - DELETE all personal/entertainment bookmarks (netflix, espn, reddit, twitter).
   - Organize the remaining New Mexico and scouting tools into exactly these 4 folders on the Bookmark Bar:
     * "Permitting" (nmfilm.com, cabq.gov, blm.gov, fs.usda.gov)
     * "Locations" (nps.gov, taospueblo.com, vla.nrao.edu)
     * "Weather & Maps" (suncalc.org, weather.gov, earthengine.google.com)
     * "Equipment & Crew" (iatse480.com, panavision.com, sunbeltrentals.com)

2. LOCATION PERMISSIONS:
   - We use interactive sun tracking and mapping constantly.
   - Go to Site Settings > Location.
   - Ensure "Sites can ask for your location" is selected.
   - Add exactly these two sites to the "Allowed to see your location" list:
     * https://earthengine.google.com:443
     * https://www.suncalc.org:443

3. SEARCH ENGINES:
   - Add a site search shortcut for Google Maps:
     * Search engine: Google Maps
     * Shortcut/Keyword: map
     * URL: https://www.google.com/maps/search/%s
   - Add a site search shortcut for Weather.com:
     * Search engine: Weather
     * Shortcut/Keyword: wx
     * URL: https://weather.com/weather/today/l/%s

4. STARTUP & DOWNLOADS:
   - On startup, open these specific pages: https://nmfilm.com and https://www.suncalc.org
   - Set the default download location to: /home/ga/Documents/Desert_Mirage_Production
   - Turn OFF "Ask where to save each file before downloading" (permits must download silently).
EOF
chown ga:ga "$SPEC_FILE"

# 4. Create Bookmarks JSON via Python
python3 << 'PYEOF'
import json
import time

chrome_base = (int(time.time()) + 11644473600) * 1000000

sites = [
    ("NM Film Office", "https://nmfilm.com/"),
    ("ABQ Film Office", "https://www.cabq.gov/film"),
    ("BLM New Mexico", "https://www.blm.gov/new-mexico"),
    ("USDA Forest Service", "https://www.fs.usda.gov/"),
    ("White Sands NPS", "https://www.nps.gov/whsa/index.htm"),
    ("Taos Pueblo", "https://taospueblo.com/"),
    ("VLA Observatory", "https://public.nrao.edu/telescopes/vla/"),
    ("SunCalc", "https://www.suncalc.org/"),
    ("ABQ Weather", "https://www.weather.gov/abq/"),
    ("Google Earth Engine", "https://earthengine.google.com/"),
    ("IATSE Local 480", "https://iatse480.com/"),
    ("Panavision", "https://www.panavision.com/"),
    ("Sunbelt Rentals", "https://www.sunbeltrentals.com/"),
    ("Georgia Film", "https://www.georgia.org/film"),
    ("Atlanta Film Office", "https://www.atlantaga.gov/government/mayor-s-office/executive-offices/office-of-film-entertainment"),
    ("Netflix", "https://www.netflix.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Twitter", "https://twitter.com/")
]

children = []
bid = 5

for i, (name, url) in enumerate(sites):
    ts = str(chrome_base - (i + 1) * 600000000)
    children.append({
        "date_added": ts,
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
        "other": {
            "children": [],
            "date_added": str(chrome_base),
            "date_modified": str(chrome_base),
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": str(chrome_base),
            "date_modified": str(chrome_base),
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

# 5. Create Default Preferences JSON (with wrong settings)
cat > "$CHROME_PROFILE/Preferences" << 'PREF_EOF'
{
   "browser": {
      "show_home_button": true
   },
   "download": {
      "default_directory": "/home/ga/Downloads",
      "prompt_for_download": true
   },
   "profile": {
      "default_content_setting_values": {
         "geolocation": 2
      }
   },
   "session": {
      "restore_on_startup": 1
   }
}
PREF_EOF
chown -R ga:ga /home/ga/.config/google-chrome/

# 6. Start Chrome and record start time
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable > /dev/null 2>&1 &"
sleep 5

# Full screen the window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Record initial state
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="