#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Drone Flight Planning Workspace ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Documents/Mission_Data/Raw_Images
chown -R ga:ga /home/ga/Documents

# Stop Chrome if running to safely modify profile
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# 1. Create Bookmarks (Flat, Unorganized)
echo "Creating flat bookmarks file..."
cat > "$CHROME_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "drone_flight_ops_initial",
   "roots": {
      "bookmark_bar": {
         "children": [
            { "date_added": "13360000000000000", "id": "101", "name": "FAA DroneZone", "type": "url", "url": "https://faadronezone.faa.gov/" },
            { "date_added": "13360000000000000", "id": "102", "name": "Aloft LAANC", "type": "url", "url": "https://app.aloft.ai/" },
            { "date_added": "13360000000000000", "id": "103", "name": "SkyVector", "type": "url", "url": "https://skyvector.com/" },
            { "date_added": "13360000000000000", "id": "104", "name": "B4UFLY", "type": "url", "url": "https://b4ufly.aloft.ai/" },
            { "date_added": "13360000000000000", "id": "105", "name": "1800wxbrief", "type": "url", "url": "https://www.1800wxbrief.com/" },
            { "date_added": "13360000000000000", "id": "106", "name": "NOTAM Search", "type": "url", "url": "https://notams.aim.faa.gov/" },
            { "date_added": "13360000000000000", "id": "201", "name": "UAV Forecast", "type": "url", "url": "https://www.uavforecast.com/" },
            { "date_added": "13360000000000000", "id": "202", "name": "Windy.com", "type": "url", "url": "https://www.windy.com/" },
            { "date_added": "13360000000000000", "id": "203", "name": "Aviation Weather Center", "type": "url", "url": "https://aviationweather.gov/" },
            { "date_added": "13360000000000000", "id": "204", "name": "Space Weather Prediction", "type": "url", "url": "https://www.swpc.noaa.gov/" },
            { "date_added": "13360000000000000", "id": "205", "name": "Astrospheric", "type": "url", "url": "https://www.astrospheric.com/" },
            { "date_added": "13360000000000000", "id": "301", "name": "DroneDeploy", "type": "url", "url": "https://www.dronedeploy.com/" },
            { "date_added": "13360000000000000", "id": "302", "name": "Pix4D", "type": "url", "url": "https://cloud.pix4d.com/" },
            { "date_added": "13360000000000000", "id": "303", "name": "Litchi Hub", "type": "url", "url": "https://flylitchi.com/hub" },
            { "date_added": "13360000000000000", "id": "304", "name": "UgCS", "type": "url", "url": "https://www.ugcs.com/" },
            { "date_added": "13360000000000000", "id": "305", "name": "Measure Ground Control", "type": "url", "url": "https://www.measure.com/" },
            { "date_added": "13360000000000000", "id": "401", "name": "DJI Enterprise", "type": "url", "url": "https://enterprise.dji.com/" },
            { "date_added": "13360000000000000", "id": "402", "name": "Autel Robotics", "type": "url", "url": "https://www.autelrobotics.com/" },
            { "date_added": "13360000000000000", "id": "403", "name": "PX4 Autopilot", "type": "url", "url": "https://px4.io/" },
            { "date_added": "13360000000000000", "id": "404", "name": "ExpressLRS", "type": "url", "url": "https://www.expresslrs.org/" },
            { "date_added": "13360000000000000", "id": "405", "name": "Betaflight", "type": "url", "url": "https://betaflight.com/" },
            { "date_added": "13360000000000000", "id": "501", "name": "Netflix", "type": "url", "url": "https://www.netflix.com/" },
            { "date_added": "13360000000000000", "id": "502", "name": "Reddit", "type": "url", "url": "https://www.reddit.com/" },
            { "date_added": "13360000000000000", "id": "503", "name": "Spotify", "type": "url", "url": "https://open.spotify.com/" }
         ],
         "date_added": "13360000000000000",
         "date_modified": "13360000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
      "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
   },
   "version": 1
}
BOOKMARKS_EOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# 2. Write Specification File
cat > /home/ga/Desktop/flight_ops_standard.txt << 'SPEC_EOF'
COMMERCIAL DRONE FLIGHT OPERATIONS - FIELD BROWSER STANDARD v2.4

1. BOOKMARKS
Organize the default flat bookmarks into exactly 5 folders on your bookmark bar:
- "Airspace": FAA DroneZone, Aloft LAANC, SkyVector, B4UFLY, 1800wxbrief, NOTAM Search
- "Weather": UAV Forecast, Windy.com, Aviation Weather Center, Space Weather Prediction, Astrospheric
- "Photogrammetry": DroneDeploy, Pix4D, Litchi Hub, UgCS, Measure Ground Control
- "Hardware": DJI Enterprise, Autel Robotics, PX4 Autopilot, ExpressLRS, Betaflight
- "Off-Duty": Netflix, Reddit, Spotify

2. GEOLOCATION (CRITICAL FOR AIRSPACE CHECKS)
Do not leave location settings on "Ask". Explicitly ALLOW location access in site settings for:
- https://app.aloft.ai
- https://www.uavforecast.com

3. DOWNLOADS (CRITICAL FOR TELEMETRY & MAPS)
- Default download location MUST be set to: /home/ga/Documents/Mission_Data/Raw_Images
- TURN OFF "Ask where to save each file before downloading" (this prevents batch map downloads from hanging).

4. CHROME EXPERIMENTAL FLAGS (chrome://flags)
Enable the following to ensure large 3D map files render correctly in the browser:
- Parallel downloading (enable-parallel-downloading)
- WebGL Draft Extensions (enable-webgl-draft-extensions)

5. CUSTOM SEARCH ENGINE
Create a shortcut to search FAA NOTAMs directly from the URL bar:
- Keyword: notam
- URL: https://notams.aim.faa.gov/notamSearch/search?notam=%s

6. STARTUP PAGES
Configure Chrome to "Open a specific page or set of pages" on startup:
- https://app.aloft.ai/
- https://www.uavforecast.com/
SPEC_EOF
chown ga:ga /home/ga/Desktop/flight_ops_standard.txt

# Start Chrome (CDP enabled)
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh &"
sleep 5

# Ensure Window is maximized
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="