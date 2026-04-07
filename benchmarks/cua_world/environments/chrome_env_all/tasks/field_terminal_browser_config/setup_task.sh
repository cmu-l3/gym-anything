#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Field Terminal Browser Config Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Stop Chrome to safely modify profile data
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 2. Prepare Chrome profile directories
CDP_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CDP_PROFILE"

# 3. Create target download directory
mkdir -p "/home/ga/Documents/Field_Reports"

# 4. Create the Specification Document on the Desktop
cat > "/home/ga/Desktop/remote_terminal_config_standard.txt" << 'DOCEOF'
═══════════════════════════════════════════════════════════════
  WINDSTREAM ENERGY SERVICES
  Remote Maintenance Terminal Configuration Standard v4.2
  Document: RMTCS-2024-042
  Effective: 2024-06-01
  Classification: INTERNAL USE ONLY
═══════════════════════════════════════════════════════════════

1. CHROME EXPERIMENTAL FLAGS (chrome://flags)
   Enable the following flags for field performance optimization:
   - Smooth Scrolling (#smooth-scrolling) -> Enabled
   - Parallel downloading (#enable-parallel-downloading) -> Enabled
   - Back-forward cache (#back-forward-cache) -> Enabled

2. DISPLAY & FONT SETTINGS
   All field tablets must be configured for outdoor readability:
   - Default font size: 20 pixels
   - Minimum font size: 14 pixels
   - Default page zoom: 125%

3. NOTIFICATION PERMISSIONS
   Default notification behavior: BLOCK
   Exceptions (ALLOW notifications):
   - [*.]vestas.com
   - [*.]bazefield.com
   - [*.]scada-international.com

4. GEOLOCATION PERMISSIONS
   Default geolocation behavior: BLOCK
   Exceptions (ALLOW geolocation):
   - [*.]windy.com
   - [*.]weather.gov
   - maps.google.com

5. HOMEPAGE & STARTUP
   - Homepage: https://www.vestas.com/en/digitalsolutions
   - On Startup: Open specific pages:
     * https://www.vestas.com/en/digitalsolutions
     * https://www.windy.com
     * https://www.weather.gov

6. DOWNLOAD MANAGEMENT
   - Default download directory: /home/ga/Documents/Field_Reports
   - Always ask where to save files: ENABLED

7. BOOKMARK ORGANIZATION
   Organize all bookmarks into the following folders on the bookmark bar:
   - "Monitoring & SCADA" — ge.com, siemens.com, schneider-electric.com, vestas.com, scada-international.com, bazefield.com, greenbyte.com
   - "Parts & Documentation" — mcmaster.com, grainger.com, rs-online.com, skf.com, fluke.com
   - "Weather & Navigation" — windy.com, earth.nullschool.net, weather.gov, maps.google.com, ventusky.com
   - "Personal" — reddit.com, youtube.com, espn.com
   No loose bookmarks should remain on the bookmark bar outside these folders.

8. PRIVACY & SECURITY
   - Password saving: DISABLED
   - Address autofill: DISABLED
   - Do Not Track: ENABLED
   - Safe Browsing: Enhanced Protection
   - Third-party cookies: BLOCKED
DOCEOF

# 5. Create Flat Bookmarks file
cat > "$CDP_PROFILE/Bookmarks" << 'BMEOF'
{
   "checksum": "0",
   "roots": {
      "bookmark_bar": {
         "children": [
            {"id": "1", "name": "GE Digital", "type": "url", "url": "https://www.ge.com/digital/"},
            {"id": "2", "name": "Siemens Energy", "type": "url", "url": "https://www.siemens-energy.com/"},
            {"id": "3", "name": "Schneider", "type": "url", "url": "https://www.schneider-electric.com/"},
            {"id": "4", "name": "Vestas Online", "type": "url", "url": "https://www.vestas.com/"},
            {"id": "5", "name": "SCADA Int", "type": "url", "url": "https://scada-international.com/"},
            {"id": "6", "name": "Bazefield", "type": "url", "url": "https://www.bazefield.com/"},
            {"id": "7", "name": "Greenbyte", "type": "url", "url": "https://www.greenbyte.com/"},
            {"id": "8", "name": "McMaster-Carr", "type": "url", "url": "https://www.mcmaster.com/"},
            {"id": "9", "name": "Grainger", "type": "url", "url": "https://www.grainger.com/"},
            {"id": "10", "name": "RS Components", "type": "url", "url": "https://www.rs-online.com/"},
            {"id": "11", "name": "SKF Bearings", "type": "url", "url": "https://www.skf.com/"},
            {"id": "12", "name": "Fluke", "type": "url", "url": "https://www.fluke.com/"},
            {"id": "13", "name": "Windy", "type": "url", "url": "https://www.windy.com/"},
            {"id": "14", "name": "Earth", "type": "url", "url": "https://earth.nullschool.net/"},
            {"id": "15", "name": "NOAA Weather", "type": "url", "url": "https://www.weather.gov/"},
            {"id": "16", "name": "Google Maps", "type": "url", "url": "https://maps.google.com/"},
            {"id": "17", "name": "Ventusky", "type": "url", "url": "https://www.ventusky.com/"},
            {"id": "18", "name": "Reddit", "type": "url", "url": "https://www.reddit.com/"},
            {"id": "19", "name": "YouTube", "type": "url", "url": "https://www.youtube.com/"},
            {"id": "20", "name": "ESPN", "type": "url", "url": "https://www.espn.com/"}
         ],
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {"children": [], "name": "Other bookmarks", "type": "folder"},
      "synced": {"children": [], "name": "Mobile bookmarks", "type": "folder"}
   },
   "version": 1
}
BMEOF

# Apply factory default preferences
cat > "$CDP_PROFILE/Preferences" << 'PREFEOF'
{
   "profile": {
      "default_content_setting_values": {
         "notifications": 1,
         "geolocation": 1,
         "cookies": 0
      },
      "password_manager_enabled": true
   },
   "autofill": {"profile_enabled": true},
   "enable_do_not_track": false,
   "safebrowsing": {"enabled": true, "enhanced": false},
   "download": {"prompt_for_download": false, "default_directory": "/home/ga/Downloads"}
}
PREFEOF

chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/Documents/Field_Reports
chown -R ga:ga /home/ga/.config/google-chrome-cdp

# Snapshot initial preferences
cp "$CDP_PROFILE/Preferences" /tmp/initial_preferences.json

# Launch Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh chrome://newtab &"
sleep 5

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Capture initial state
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="