#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Broadcast Meteorologist Workspace Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Stop Chrome if running to safely modify profile
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Prepare directories
mkdir -p /home/ga/Documents/Weather_Graphics
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Documents/Weather_Graphics

# Create the specification file
cat > /home/ga/Desktop/weather_wall_config.txt << 'EOF'
STATION WXYZ WEATHER WALL - BROWSER STANDARD CONFIGURATION

As the broadcast meteorologist, your live-air browser must be completely deterministic. 
Pop-ups, notification dings, or location prompts over the air are unacceptable.

1. BOOKMARK ORGANIZATION
Organize the 26 loose bookmarks into the following 4 folders on the bookmark bar:
- "Live Radar" (NWS Radar, AccuWeather, RadarScope, MyRadar, IntelliWeather, Weather Underground, Weather.com)
- "Satellite Imaging" (GOES, RAMMB, Zoom Earth, COD Satrad, SSEC)
- "Forecast Models" (Pivotal Weather, Tropical Tidbits, NCEP, SPC HREF, Windy, WeatherBell)
- "Off-Air" (YouTube, Facebook, Twitter, CNN, ESPN, Netflix, Amazon)

2. SITE PERMISSIONS (CRITICAL)
- Location: Add "https://radar.weather.gov" to the explicitly Allowed list (so radar auto-centers without prompting).
- Notifications: Set default to "Don't allow sites to send notifications" (Block).
- Pop-ups & Redirects: Set default to "Don't allow" (Block).

3. DOWNLOADS
- Set location to: /home/ga/Documents/Weather_Graphics
- Disable "Ask where to save each file before downloading" (we need instant saving during live segments).

4. CUSTOM SEARCH ENGINE
- Name: Aviation Weather METAR
- Keyword: metar
- URL: https://aviationweather.gov/data/metar/?id=%s

5. STARTUP
- Set browser to "Open a specific page or set of pages"
- Add: https://radar.weather.gov/
- Add: https://www.star.nesdis.noaa.gov/GOES/

6. PRIVACY / CREDENTIALS
- Disable "Offer to save passwords"
- Disable Address Autofill
- Disable Payment Methods Autofill
(Prevents private credentials from flashing on the broadcast screen).
EOF
chown ga:ga /home/ga/Desktop/weather_wall_config.txt

# Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# Generate Bookmarks JSON using Python
echo "Generating initial bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

# Grouped data for initial flat seeding
bookmarks_data = [
    # Radars
    ("NWS Radar", "https://radar.weather.gov/"),
    ("Weather.com Radar", "https://weather.com/weather/radar/interactive/"),
    ("AccuWeather Radar", "https://www.accuweather.com/en/us/national/weather-radar"),
    ("RadarScope", "https://www.radarscope.app/"),
    ("WU Radar", "https://www.wunderground.com/radar/us"),
    ("IntelliWeather", "https://www.intelliweather.com/"),
    ("MyRadar", "https://myradar.com/"),
    # Satellites
    ("GOES Image Viewer", "https://goes.gsfc.nasa.gov/"),
    ("NOAA STAR GOES", "https://www.star.nesdis.noaa.gov/GOES/"),
    ("RAMMB Slider", "https://rammb-slider.cira.colostate.edu/"),
    ("Zoom Earth", "https://zoom.earth/"),
    ("COD Satrad", "https://weather.cod.edu/satrad/"),
    ("SSEC RealEarth", "https://realearth.ssec.wisc.edu/"),
    # Models
    ("Pivotal Weather", "https://www.pivotalweather.com/model.php"),
    ("Tropical Tidbits", "https://www.tropicaltidbits.com/analysis/models/"),
    ("NCEP MAG", "https://mag.ncep.noaa.gov/"),
    ("SPC HREF", "https://www.spc.noaa.gov/exper/href/"),
    ("Windy", "https://www.windy.com/"),
    ("WeatherBell", "https://models.weatherbell.com/"),
    # Off-Air
    ("YouTube", "https://www.youtube.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Twitter", "https://twitter.com/"),
    ("CNN", "https://www.cnn.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Amazon", "https://www.amazon.com/")
]

children = []
bid = 5

for name, url in bookmarks_data:
    children.append({
        "date_added": str(chrome_base - bid * 600000000),
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
            "date_added": str(chrome_base - 100000000000),
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

chown -R ga:ga /home/ga/.config/google-chrome/

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-default-browser-check > /dev/null 2>&1 &"
sleep 5

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="