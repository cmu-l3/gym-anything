#!/usr/bin/env bash
set -euo pipefail

echo "=== Dispatch Terminal Config Task Setup ==="
echo "Task: Configure browser per 911 Terminal Configuration Standard"

# Wait for environment to stabilize
sleep 2

# 1. Stop Chrome to safely modify profile data
echo "Stopping Chrome to inject test data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 2. Prepare Chrome profile directories
# We target both standard and CDP directories
CHROME_CDP_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
CHROME_CDP_BASE="/home/ga/.config/google-chrome-cdp"
mkdir -p "$CHROME_CDP_PROFILE"
mkdir -p "$CHROME_CDP_BASE"

# 3. Create Bookmarks JSON with 20 flat bookmarks
echo "Creating flat bookmarks on the bookmark bar..."
cat > "$CHROME_CDP_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "dispatch_initial",
   "roots": {
      "bookmark_bar": {
         "children": [
            {"id": "101", "name": "FEMA", "type": "url", "url": "https://www.fema.gov/"},
            {"id": "102", "name": "National Weather Service", "type": "url", "url": "https://www.weather.gov/"},
            {"id": "103", "name": "USGS Earthquakes", "type": "url", "url": "https://earthquake.usgs.gov/"},
            {"id": "104", "name": "NOAA", "type": "url", "url": "https://www.noaa.gov/"},
            {"id": "105", "name": "Ready.gov", "type": "url", "url": "https://www.ready.gov/"},
            {"id": "106", "name": "CDC Emergency Preparedness", "type": "url", "url": "https://emergency.cdc.gov/"},
            {"id": "107", "name": "DHS", "type": "url", "url": "https://www.dhs.gov/"},
            {"id": "108", "name": "NIMS", "type": "url", "url": "https://www.fema.gov/emergency-managers/nims"},
            {"id": "109", "name": "Google Maps", "type": "url", "url": "https://maps.google.com/"},
            {"id": "110", "name": "Bing Maps", "type": "url", "url": "https://www.bing.com/maps"},
            {"id": "111", "name": "OpenStreetMap", "type": "url", "url": "https://www.openstreetmap.org/"},
            {"id": "112", "name": "ArcGIS", "type": "url", "url": "https://www.arcgis.com/"},
            {"id": "113", "name": "NFPA", "type": "url", "url": "https://www.nfpa.org/"},
            {"id": "114", "name": "IAFC", "type": "url", "url": "https://www.iafc.org/"},
            {"id": "115", "name": "APCO International", "type": "url", "url": "https://www.apcointl.org/"},
            {"id": "116", "name": "YouTube", "type": "url", "url": "https://www.youtube.com/"},
            {"id": "117", "name": "Netflix", "type": "url", "url": "https://www.netflix.com/"},
            {"id": "118", "name": "ESPN", "type": "url", "url": "https://www.espn.com/"},
            {"id": "119", "name": "Reddit", "type": "url", "url": "https://www.reddit.com/"},
            {"id": "120", "name": "Amazon", "type": "url", "url": "https://www.amazon.com/"}
         ],
         "date_added": "13360000000000000",
         "date_modified": "13360000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
      "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
   },
   "version": 1
}
BOOKMARKS_EOF

# 4. Write Configuration Standard to Desktop
echo "Creating Terminal Configuration Standard document..."
cat > "/home/ga/Desktop/dispatch_terminal_standard.txt" << 'STANDARD_EOF'
==================================================================
  METRO COUNTY 911 COMMUNICATIONS CENTER
  Terminal Configuration Standard — TCS-2025-017
  Effective: 2025-06-01
  Classification: INTERNAL USE
==================================================================

SECTION 1 — CHROME EXPERIMENTS (chrome://flags)

Enable the following experiments for terminal stability and
performance on 24/7 dispatch workstations:

  1. Smooth Scrolling        → Enabled
     (flag name: smooth-scrolling)
  2. Parallel Downloading     → Enabled
     (flag name: enable-parallel-downloading)
  3. Experimental QUIC protocol → Enabled
     (flag name: enable-quic)

NOTE: After enabling, Chrome will prompt to relaunch. You may
relaunch when all other configuration is complete.

------------------------------------------------------------------
SECTION 2 — DISPLAY & READABILITY

Dispatch terminals use 32" monitors at arm's length. Configure:

  • Default font size: 20
  • Minimum font size: 14

Access via chrome://settings/appearance or Settings > Appearance.

------------------------------------------------------------------
SECTION 3 — SITE-SPECIFIC PERMISSIONS

3a. GEOLOCATION — ALLOW for mapping portals (dispatchers must
    share terminal location for proximity calculations):

    https://maps.google.com
    https://www.arcgis.com
    https://www.openstreetmap.org

3b. NOTIFICATIONS — ALLOW for real-time alert feeds:

    https://www.weather.gov
    https://earthquake.usgs.gov
    https://www.noaa.gov

3c. DEFAULT NOTIFICATION POLICY — BLOCK
    All sites not explicitly listed above must have notifications
    blocked by default.

------------------------------------------------------------------
SECTION 4 — BOOKMARK ORGANIZATION

Organize all bookmarks into the following folders on the
bookmark bar. No loose bookmarks should remain on the bar.

  Folder: "Emergency Services"
    • FEMA (fema.gov)
    • Ready.gov
    • CDC Emergency Preparedness (emergency.cdc.gov)
    • DHS (dhs.gov)
    • NIMS (fema.gov/emergency-managers/nims)
    • NFPA (nfpa.org)
    • IAFC (iafc.org)
    • APCO International (apcointl.org)

  Folder: "Weather & Hazards"
    • National Weather Service (weather.gov)
    • NOAA (noaa.gov)
    • USGS Earthquakes (earthquake.usgs.gov)

  Folder: "Mapping & GIS"
    • Google Maps (maps.google.com)
    • Bing Maps (bing.com/maps)
    • OpenStreetMap (openstreetmap.org)
    • ArcGIS (arcgis.com)

  Folder: "Personal (Off-Duty)"
    • Any non-work bookmarks (YouTube, Netflix, ESPN, Reddit,
      Amazon, etc.) — move here, do not delete.

------------------------------------------------------------------
SECTION 5 — HOMEPAGE & STARTUP

  • Homepage: https://www.weather.gov
  • On startup, open the following pages:
      1. https://www.weather.gov
      2. https://earthquake.usgs.gov
      3. https://www.fema.gov

------------------------------------------------------------------
SECTION 6 — DOWNLOADS

  • Default download directory:
      /home/ga/Documents/Dispatch_Records
  • Always ask where to save files: ENABLED

------------------------------------------------------------------
SECTION 7 — CREDENTIAL & AUTOFILL SECURITY

Shared terminals must NOT store personal credentials:

  • Offer to save passwords: DISABLED
  • Auto-fill addresses: DISABLED
  • Payment methods: DISABLED

==================================================================
END OF STANDARD TCS-2025-017
==================================================================
STANDARD_EOF

# 5. Create Target Download Directory
mkdir -p "/home/ga/Documents/Dispatch_Records"

# Fix permissions
chown -R ga:ga "/home/ga/.config"
chown -R ga:ga "/home/ga/Desktop"
chown -R ga:ga "/home/ga/Documents"

# 6. Record timestamp for anti-gaming (verification checks file mtimes against this)
date +%s > /tmp/task_start_time.txt

# 7. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh > /dev/null 2>&1 &"
sleep 5

# Focus and Maximize
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# 8. Take Initial Screenshot
echo "Taking initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="