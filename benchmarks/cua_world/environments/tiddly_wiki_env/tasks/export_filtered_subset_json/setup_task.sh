#!/bin/bash
echo "=== Setting up export_filtered_subset_json task ==="

source /workspace/scripts/task_utils.sh

# Ensure target directory exists and is clean
su - ga -c "mkdir -p /home/ga/Documents"
rm -f /home/ga/Documents/Habitable_Terrestrials.json
rm -f /home/ga/Downloads/*.json

# Remove any pre-existing log tiddler
rm -f /home/ga/mywiki/tiddlers/Export_Log.tid 2>/dev/null || true

# Seed the Exoplanet dataset directly as .tid files
su - ga -c 'python3 - << "PYEOF"
import os
import json

tiddlers_dir = "/home/ga/mywiki/tiddlers"
os.makedirs(tiddlers_dir, exist_ok=True)

planets = [
    {"title": "TRAPPIST-1 d", "tags": "Terrestrial HabitableZone", "discovery_year": "2016", "mass": "0.388", "radius": "0.788"},
    {"title": "TRAPPIST-1 e", "tags": "Terrestrial HabitableZone", "discovery_year": "2017", "mass": "0.692", "radius": "0.920"},
    {"title": "Proxima Centauri b", "tags": "Terrestrial HabitableZone", "discovery_year": "2016", "mass": "1.27", "radius": "1.08"},
    {"title": "Kepler-186f", "tags": "Terrestrial HabitableZone", "discovery_year": "2014", "mass": "1.44", "radius": "1.17"},
    {"title": "Teegarden\'s Star b", "tags": "Terrestrial HabitableZone", "discovery_year": "2019", "mass": "1.05", "radius": "1.02"},
    {"title": "LHS 1140 b", "tags": "Terrestrial HabitableZone", "discovery_year": "2017", "mass": "6.98", "radius": "1.73"},
    {"title": "K2-72e", "tags": "Terrestrial HabitableZone", "discovery_year": "2016", "mass": "2.21", "radius": "1.29"},
    {"title": "Gliese 667 Cc", "tags": "Terrestrial HabitableZone", "discovery_year": "2011", "mass": "3.8", "radius": "1.5"},
    {"title": "Kepler-10b", "tags": "Terrestrial", "discovery_year": "2011", "mass": "4.6", "radius": "1.47"},
    {"title": "CoRoT-7b", "tags": "Terrestrial", "discovery_year": "2009", "mass": "4.73", "radius": "1.58"},
    {"title": "55 Cancri e", "tags": "Terrestrial", "discovery_year": "2004", "mass": "7.99", "radius": "1.875"},
    {"title": "Kepler-78b", "tags": "Terrestrial", "discovery_year": "2013", "mass": "1.86", "radius": "1.173"},
    {"title": "HD 219134 b", "tags": "Terrestrial", "discovery_year": "2015", "mass": "4.74", "radius": "1.602"},
    {"title": "LHS 3844 b", "tags": "Terrestrial", "discovery_year": "2018", "mass": "2.25", "radius": "1.303"},
    {"title": "K2-18b", "tags": "HabitableZone", "discovery_year": "2015", "mass": "8.63", "radius": "2.61"},
    {"title": "Kepler-22b", "tags": "HabitableZone", "discovery_year": "2011", "mass": "36", "radius": "2.38"},
    {"title": "Kepler-452b", "tags": "HabitableZone", "discovery_year": "2015", "mass": "5", "radius": "1.63"},
    {"title": "Kepler-62f", "tags": "HabitableZone", "discovery_year": "2013", "mass": "35", "radius": "1.41"},
    {"title": "Kepler-442b", "tags": "HabitableZone", "discovery_year": "2015", "mass": "2.34", "radius": "1.34"},
    {"title": "Gliese 581g", "tags": "HabitableZone", "discovery_year": "2010", "mass": "3.1", "radius": "1.5"},
    {"title": "51 Pegasi b", "tags": "GasGiant", "discovery_year": "1995", "mass": "150", "radius": "13.4"},
    {"title": "WASP-12b", "tags": "GasGiant Transit", "discovery_year": "2008", "mass": "447", "radius": "21"},
    {"title": "HD 209458 b", "tags": "GasGiant Transit", "discovery_year": "1999", "mass": "219", "radius": "15.4"},
    {"title": "Kepler-7b", "tags": "GasGiant", "discovery_year": "2010", "mass": "137", "radius": "18"},
    {"title": "TrES-2b", "tags": "GasGiant Transit", "discovery_year": "2006", "mass": "380", "radius": "14.2"}
]

for p in planets:
    filename = p["title"].replace(" ", "_").replace("\'", "") + ".tid"
    filepath = os.path.join(tiddlers_dir, filename)
    content = f"title: {p['title']}\ntags: {p['tags']}\ndiscovery_year: {p['discovery_year']}\nmass: {p['mass']}\nradius: {p['radius']}\ntype: text/vnd.tiddlywiki\n\nThis is the record for exoplanet {p['title']}."
    with open(filepath, "w") as f:
        f.write(content)
PYEOF
'

# Restart TiddlyWiki to safely load the new seeded tiddlers
echo "Restarting TiddlyWiki to ingest data..."
pkill -f tiddlywiki 2>/dev/null || true
sleep 2

su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to come back up
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is back online"
        break
    fi
    sleep 1
done

# Focus Firefox and refresh page to show new content
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5 2>/dev/null || true
sleep 2

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="