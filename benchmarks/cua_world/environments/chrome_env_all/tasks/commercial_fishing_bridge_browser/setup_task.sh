#!/bin/bash
set -euo pipefail

echo "=== Commercial Fishing Bridge Browser Task Setup ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Create required download directory
mkdir -p /home/ga/Documents/Catch_Logs
chown -R ga:ga /home/ga/Documents/Catch_Logs

# Stop Chrome if running to safely modify profile
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# Clean up any existing state
rm -f "$CHROME_PROFILE/Preferences"
rm -f "/home/ga/.config/google-chrome/Local State"
rm -f "$CHROME_PROFILE/Web Data"

echo "Creating initial bookmarks (flat, unorganized)..."
python3 << 'PYEOF'
import json
import time
import uuid
import os

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_list = [
    ("Weather", "weather.gov/marine"),
    ("Ocean Weather", "ocean.weather.gov"),
    ("Marine Rutgers", "marine.rutgers.edu"),
    ("OSCAR Currents", "oscar.noaa.gov"),
    ("Buoy Bay", "buoybay.noaa.gov"),
    ("Passage Weather", "passageweather.com"),
    ("Windy", "windy.com"),
    ("MarineTraffic", "marinetraffic.com"),
    ("VesselFinder", "vesselfinder.com"),
    ("MyShipTracking", "myshiptracking.com"),
    ("SAFIS Reporting", "safis.accsp.org"),
    ("GARFO FishOnline", "fishonline.garfo.noaa.gov"),
    ("WDFW Commercial", "wdfw.wa.gov/fishing/commercial"),
    ("Port of Seattle", "portofseattle.org"),
    ("Port of Alaska", "portofalaska.com"),
    ("SF Port", "sfport.com"),
    ("Netflix", "netflix.com"),
    ("Facebook", "facebook.com"),
    ("YouTube", "youtube.com"),
    ("ESPN", "espn.com"),
    ("Amazon", "amazon.com")
]

children = []
bid = 5

for i, (name, domain) in enumerate(bookmarks_list):
    ts = str(chrome_base - (i + 1) * 600000000)
    children.append({
        "date_added": ts,
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": f"https://www.{domain}" if not domain.startswith("http") else domain
    })
    bid += 1

bookmarks_json = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base - 86400000000),
            "date_modified": str(chrome_base),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": str(chrome_base - 86400000000),
            "date_modified": "0",
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": str(chrome_base - 86400000000),
            "date_modified": "0",
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

os.makedirs("/home/ga/.config/google-chrome/Default", exist_ok=True)
with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks_json, f, indent=3)
PYEOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check about:blank &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="