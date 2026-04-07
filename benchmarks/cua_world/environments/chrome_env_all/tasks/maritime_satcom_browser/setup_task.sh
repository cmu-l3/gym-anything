#!/usr/bin/env bash
set -euo pipefail

echo "=== Maritime Satcom Browser Optimization Task Setup ==="

# 1. Kill any running Chrome to safely modify profile data
echo "Stopping Chrome to set up task data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# 2. Set up Chrome profile directories
CHROME_DIR="/home/ga/.config/google-chrome"
CHROME_PROFILE="$CHROME_DIR/Default"
mkdir -p "$CHROME_PROFILE"

# 3. Create Bookmarks JSON with 28 flat bookmarks
echo "Generating initial bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

maritime_weather = [
    ("NOAA NDBC", "https://www.ndbc.noaa.gov/"),
    ("Windy", "https://www.windy.com/"),
    ("PassageWeather", "https://www.passageweather.com/"),
    ("Buoyweather", "https://www.buoyweather.com/"),
    ("OceanPrediction", "https://ocean.weather.gov/"),
    ("NHC", "https://www.nhc.noaa.gov/"),
    ("TidesAndCurrents", "https://tidesandcurrents.noaa.gov/"),
    ("NWS Marine", "https://www.weather.gov/marine/")
]

port_gov = [
    ("USCG Navigation Center", "https://www.navcen.uscg.gov/"),
    ("CBP Roam", "https://www.cbp.gov/travel/pleasure-boats/cbp-roam"),
    ("Port of Seattle", "https://www.portseattle.org/"),
    ("Pacific Fishery Management", "https://www.pcouncil.org/"),
    ("NMFS", "https://www.fisheries.noaa.gov/"),
    ("FCC", "https://www.fcc.gov/")
]

vessel_ops = [
    ("Inmarsat", "https://www.inmarsat.com/"),
    ("Iridium", "https://www.iridium.com/"),
    ("SeafoodNet", "https://www.seafoodnet.com/"),
    ("FishChoice", "https://fishchoice.com/"),
    ("VesselTracker", "https://www.vesseltracker.com/"),
    ("MarineTraffic", "https://www.marinetraffic.com/")
]

streaming = [
    ("YouTube", "https://www.youtube.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Spotify", "https://open.spotify.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("TikTok", "https://www.tiktok.com/"),
    ("Twitch", "https://www.twitch.tv/"),
    ("Hulu", "https://www.hulu.com/"),
    ("Disney+", "https://www.disneyplus.com/")
]

all_bookmarks = maritime_weather + port_gov + vessel_ops + streaming

children = []
bid = 5

for i, (name, url) in enumerate(all_bookmarks):
    ts = str(chrome_base - (i + 1) * 600000000)
    children.append({
        "date_added": ts,
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

profile_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_dir, exist_ok=True)
with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

# Fix permissions
chown -R ga:ga "$CHROME_DIR"

# 4. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"
sleep 5

# Focus and maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# 5. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="