#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Aquaculture Monitoring Terminal Task ==="
echo "Task: Configure Chrome for 24/7 hatchery IoT monitoring"

# Wait for environment to stabilize
sleep 2

# Kill any existing Chrome processes to safely modify profile data
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create the Hatchery Terminal Spec file
cat > /home/ga/Desktop/hatchery_terminal_spec.txt << 'SPEC_EOF'
AQUACULTURE FACILITY - WORKSTATION CONFIGURATION SPEC
-----------------------------------------------------

1. BOOKMARK ORGANIZATION
Create the following folders on the Bookmark Bar and sort the existing work-related bookmarks into them:
- "Environment" (Weather, USGS, NOAA, Tides)
- "Fish Health" (FDA, USDA, WOAH, FishBase)
- "Feed Logistics" (Skretting, BioMar, Pentair, Hach)
- "Local Sensors" (The three 10.0.0.x IP addresses)

2. SECURITY & COMPLIANCE
Overnight staff have left personal bookmarks on this terminal.
- Permanently DELETE all entertainment bookmarks (YouTube, Reddit, Netflix, Hulu, Twitch, Steam, Facebook). Do not just hide them.

3. STARTUP CONFIGURATION
- Configure Chrome to open these specific pages on startup:
  1) https://tidesandcurrents.noaa.gov/
  2) http://10.0.0.50/dashboard

4. PERFORMANCE & DASHBOARD UPTIME (CRITICAL)
Chrome's Memory Saver feature puts inactive tabs to sleep, which breaks our live dashboard sockets.
- Navigate to Settings > Performance.
- Add the following to the "Always keep these sites active" list:
  10.0.0.50
  10.0.0.51
  10.0.0.52
  tidesandcurrents.noaa.gov

5. SENSOR CONNECTIVITY (INSECURE CONTENT)
Our local sensors do not have SSL certificates and use HTTP.
- Navigate to Settings > Privacy and security > Site settings > Insecure content.
- Add the three local IPs (10.0.0.50, 10.0.0.51, 10.0.0.52) to the Allowed list to suppress mixed-content blocking.

6. CUSTOM SEARCH ENGINES
Add two custom search engines to help staff quickly look up information:
- Keyword: fb
  URL: https://www.fishbase.se/Summary/SpeciesSummary.php?id=%s
- Keyword: hach
  URL: https://www.hach.com/search?q=%s
SPEC_EOF
chown ga:ga /home/ga/Desktop/hatchery_terminal_spec.txt

# Generate Bookmarks JSON using Python
echo "Generating initial bookmarks..."
python3 << 'PYEOF'
import json
import time

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_list = [
    # Environment
    ("NOAA Tides", "https://tidesandcurrents.noaa.gov/"),
    ("USGS Water Data", "https://waterdata.usgs.gov/"),
    ("Weather Channel", "https://weather.com/"),
    ("National Data Buoy", "https://www.ndbc.noaa.gov/"),
    # Fish Health
    ("FishBase", "https://www.fishbase.se/"),
    ("FDA Animal Drugs", "https://animaldrugsatfda.fda.gov/"),
    ("USDA APHIS", "https://www.aphis.usda.gov/"),
    ("World Org Animal Health", "https://www.woah.org/"),
    # Feed & Equipment
    ("Skretting Feed", "https://www.skretting.com/"),
    ("BioMar Aquaculture", "https://www.biomar.com/"),
    ("Pentair Aquatic", "https://pentairaes.com/"),
    ("Hach Water Analysis", "https://www.hach.com/"),
    # Local Sensors
    ("Main Tank Dashboard", "http://10.0.0.50/dashboard"),
    ("Pump Diagnostics", "http://10.0.0.51/pumps"),
    ("DO Sensors Array", "http://10.0.0.52/do-sensors"),
    # Unauthorized
    ("YouTube", "https://www.youtube.com/"),
    ("Reddit Gaming", "https://www.reddit.com/r/gaming/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Hulu", "https://www.hulu.com/"),
    ("Twitch", "https://www.twitch.tv/"),
    ("Steam", "https://store.steampowered.com/"),
    ("Facebook", "https://www.facebook.com/")
]

children = []
for i, (name, url) in enumerate(bookmarks_list):
    ts = str(chrome_base - (i * 1000000))
    children.append({
        "date_added": ts,
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "initial_hatchery_state",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": str(chrome_base),
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": str(chrome_base),
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Generate default preferences (Memory Saver is ON by default)
cat > "$CHROME_PROFILE/Preferences" << 'PREF_EOF'
{
   "browser": {
      "show_home_button": true
   },
   "performance_tuning": {
      "high_efficiency_mode": {
         "state": 1
      }
   }
}
PREF_EOF
chown ga:ga "$CHROME_PROFILE/Preferences"

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /tmp/chrome_setup.log 2>&1 &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="