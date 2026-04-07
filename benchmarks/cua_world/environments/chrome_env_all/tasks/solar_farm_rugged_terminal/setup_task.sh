#!/usr/bin/env bash
set -euo pipefail

echo "=== Solar Farm Rugged Terminal Task Setup ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Documents/SCADA_Exports
mkdir -p /home/ga/.config/google-chrome/Default

# 1. Stop Chrome safely before modifying profile
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# 2. Write the Specification Document
cat > /home/ga/Desktop/solar_terminal_config.txt << 'EOF'
SOLAR FARM FIELD TERMINAL - BROWSER CONFIGURATION STANDARD v4.2

1. BOOKMARK ORGANIZATION
Organize the existing bookmarks into exactly these 4 folders on the Bookmark Bar:
  - "SCADA & Telemetry" (SMA, Sungrow, AlsoEnergy, SCADA Intl, Ignition)
  - "Weather & Irradiance" (NREL, Solcast, NOAA, Meteonorm, Vaisala)
  - "Grid Market Data" (CAISO, ERCOT, PJM, SPP)
  - "Equipment Docs" (First Solar, Nextracker, Shoals, ABB, Yaskawa)

2. DATA HYGIENE
  - DELETE all personal and entertainment bookmarks (Reddit, Netflix, ESPN, Amazon, Facebook, Twitter). Do NOT archive them.

3. OUTDOOR ACCESSIBILITY
  - Set Chrome's Default Font Size to Large/Custom: 22 (for high-glare readability).
  - Navigate to chrome://flags and ENABLE:
      * Overlay Scrollbars
      * Smooth Scrolling

4. SEARCH SHORTCUTS
  - Create a custom site search shortcut:
      * Name: Inverter Faults DB
      * Shortcut (Keyword): fault
      * URL: https://www.inverter-faults-db.com/search?code=%s

5. BROWSER PREFERENCES
  - Show Home Button & set Homepage to: https://www.caiso.com/TodaysOutlook/Pages/default.aspx
  - Set Default Download Location to: /home/ga/Documents/SCADA_Exports
  - Enable "Ask where to save each file before downloading"
  - Disable "Offer to save passwords"
  - Disable "Save and fill addresses"
EOF

# 3. Create the flat Bookmarks file via Python script to handle JSON encoding cleanly
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_data = [
    # SCADA
    ("SMA Sunny Portal", "https://www.sunnyportal.com/"),
    ("Sungrow iSolarCloud", "https://www.isolarcloud.com/"),
    ("AlsoEnergy", "https://www.alsoenergy.com/"),
    ("SCADA International", "https://scada-international.com/"),
    ("Ignition Perspective", "https://inductiveautomation.com/"),
    # Weather
    ("NREL NSRDB", "https://nsrdb.nrel.gov/"),
    ("Solcast", "https://solcast.com/"),
    ("NOAA Aviation Weather", "https://aviationweather.gov/"),
    ("Meteonorm", "https://meteonorm.com/"),
    ("Vaisala", "https://www.vaisala.com/"),
    # Grid
    ("CAISO Today's Outlook", "https://www.caiso.com/TodaysOutlook/Pages/default.aspx"),
    ("ERCOT Real-Time", "https://www.ercot.com/"),
    ("PJM Markets", "https://www.pjm.com/"),
    ("SPP Grid", "https://www.spp.org/"),
    # Equipment
    ("First Solar Datasheets", "https://www.firstsolar.com/"),
    ("Nextracker Manuals", "https://www.nextracker.com/"),
    ("Shoals Combiner Specs", "https://www.shoals.com/"),
    ("ABB Inverter Docs", "https://global.abb/group/en"),
    ("Yaskawa Manuals", "https://www.yaskawa.com/"),
    # Personal (To be deleted)
    ("Reddit", "https://www.reddit.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Twitter", "https://twitter.com/")
]

children = []
for i, (name, url) in enumerate(bookmarks_data):
    children.append({
        "date_added": str(chrome_base - i * 600000000),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": "0",
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

# Fix permissions
chown -R ga:ga /home/ga/.config/google-chrome
chown -R ga:ga /home/ga/Desktop/solar_terminal_config.txt
chown -R ga:ga /home/ga/Documents/SCADA_Exports

# 4. Launch Chrome so the user sees the flat bookmarks immediately
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check &"
sleep 5

# Fullscreen and screenshot
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="