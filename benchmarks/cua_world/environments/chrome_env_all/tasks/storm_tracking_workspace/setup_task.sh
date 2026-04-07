#!/bin/bash
# Setup script for storm_tracking_workspace task
set -euo pipefail

echo "=== Storm Tracking Workspace Task Setup ==="
echo "Task: Reconfigure browser for severe weather monitoring"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for environment to be ready
sleep 2

# Kill any running Chrome to safely modify profile
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# Create download directory
mkdir -p "/home/ga/Documents/Weather_Data"

# Create the NWS Browser Standard Spec File
cat > "/home/ga/Desktop/nws_browser_standard.txt" << 'SPEC_EOF'
NATIONAL WEATHER SERVICE - FORECAST OFFICE
OPERATIONAL BROWSER STANDARD (WFO-STD-2025-01)

§1 PURPOSE
This document outlines the mandatory Chrome browser configuration for all operational meteorologist workstations to ensure rapid data access and security compliance during severe weather events.

§2 BOOKMARK ORGANIZATION
All loose bookmarks MUST be organized into the following strict folder structure on the Bookmark Bar:
1. "Radar & Satellite" (Includes NEXRAD, GOES, NESDIS, Lightning, Aviation, Ocean, WPC)
2. "Model Data" (Includes Tropical Tidbits, Pivotal Weather, MAG, NCEP, ECMWF, COD)
3. "Observations" (Includes MesoWest, RUC Soundings, NDBC, NWS Surface Obs, MADIS)
4. "Warning Coordination" (Includes SPC, NHC, NWSChat, Alerts)
5. "Climate & Verification" (Includes NCEI, Climate.gov, SPC Reports)
6. "Off-Duty" (All personal/entertainment sites must be segregated into this folder)
NO bookmarks may be left loose on the top-level bookmark bar.

§3 SEARCH ENGINE SHORTCUTS
Configure the following custom search engines to accelerate database queries:
- Keyword "radar" -> https://radar.weather.gov/station/{searchTerms}
- Keyword "spc"   -> https://www.spc.noaa.gov/cgi-bin/search?query={searchTerms}
- Keyword "nhc"   -> https://www.nhc.noaa.gov/search.php?q={searchTerms}

§4 HOMEPAGE AND STARTUP
- Homepage: Must be set exactly to https://www.weather.gov
- Startup: Browser must open specific pages on startup:
  1) https://radar.weather.gov
  2) https://www.spc.noaa.gov

§5 PRIVACY AND SECURITY (MANDATORY)
- Third-party cookies: BLOCKED
- Do Not Track: ENABLED
- Safe Browsing: ENHANCED PROTECTION mode
- Password Saving: DISABLED
- Address/Form Autofill: DISABLED

§6 DOWNLOAD MANAGEMENT
- Default Download Location: /home/ga/Documents/Weather_Data
- "Ask where to save each file before downloading": ENABLED

§7 CONFIGURATION DOCUMENTATION
Upon completion, the forecaster must write a shift-handoff summary to ~/Desktop/config_handoff.txt. The summary must briefly mention that bookmark folders were created, search shortcuts were added, and the homepage was updated to weather.gov.
SPEC_EOF

# Set permissions
chown -R ga:ga "/home/ga/Desktop"
chown -R ga:ga "/home/ga/Documents"

# Create Initial Bookmarks (32 bookmarks scattered FLAT on bookmark bar)
echo "Creating initial bookmarks (flat, unorganized)..."
python3 << 'PYEOF'
import json
import time

chrome_base = (int(time.time()) + 11644473600) * 1000000

sites = [
    ("NEXRAD Radar - NWS", "https://radar.weather.gov/"),
    ("GOES Satellite Imagery", "https://www.goes.noaa.gov/"),
    ("NESDIS STAR Products", "https://www.star.nesdis.noaa.gov/"),
    ("Real-Time Lightning Map", "https://www.lightningmaps.org/"),
    ("Aviation Weather Center", "https://aviationweather.gov/"),
    ("Ocean Prediction Center", "https://ocean.weather.gov/"),
    ("Weather Prediction Center", "https://www.wpc.ncep.noaa.gov/"),
    ("Tropical Tidbits - Models", "https://www.tropicaltidbits.com/"),
    ("Pivotal Weather", "https://www.pivotalweather.com/"),
    ("MAG - Model Analysis", "https://mag.ncep.noaa.gov/"),
    ("NCEP Home", "https://www.ncep.noaa.gov/"),
    ("ECMWF Charts", "https://www.ecmwf.int/"),
    ("COD Weather Models", "https://weather.cod.edu/"),
    ("MesoWest Observations", "https://mesowest.utah.edu/"),
    ("RUC Soundings", "https://rucsoundings.noaa.gov/"),
    ("NDBC Buoy Data", "https://www.ndbc.noaa.gov/"),
    ("NWS Surface Obs", "https://www.weather.gov/wrh/timeseries"),
    ("MADIS Observations", "https://madis-data.ncep.noaa.gov/"),
    ("Storm Prediction Center", "https://www.spc.noaa.gov/"),
    ("National Hurricane Center", "https://www.nhc.noaa.gov/"),
    ("NWSChat", "https://nwschat.weather.gov/"),
    ("NWS Alerts", "https://alerts.weather.gov/"),
    ("NCEI Climate Data", "https://www.ncei.noaa.gov/"),
    ("Climate.gov", "https://www.climate.gov/"),
    ("SPC Storm Reports", "https://www.spc.noaa.gov/climo/reports/today.html"),
    ("YouTube", "https://www.youtube.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Spotify", "https://open.spotify.com/"),
    ("Instagram", "https://www.instagram.com/")
]

children = []
for i, (name, url) in enumerate(sites):
    children.append({
        "date_added": str(chrome_base - (35 - i) * 600000000),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "storm_tracking_initial_state",
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

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown ga:ga "/home/ga/.config/google-chrome/Default/Bookmarks"

# Record initial bookmarks hash for anti-gaming verification
md5sum "/home/ga/.config/google-chrome/Default/Bookmarks" | awk '{print $1}' > /tmp/initial_bookmarks_hash.txt

# Start Chrome in the background
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check --remote-debugging-port=9222 &"
sleep 5

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="