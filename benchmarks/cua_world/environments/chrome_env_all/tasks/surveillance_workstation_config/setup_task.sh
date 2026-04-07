#!/usr/bin/env bash
set -euo pipefail

echo "=== Disease Surveillance Browser Configuration Task Setup ==="
echo "Task: Configure browser per state public health department standard"

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Wait for environment to be ready
sleep 2

# Kill any running Chrome to safely modify profile
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true

# Set up Chrome profile directories
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp"
mkdir -p "$CHROME_PROFILE/Default"
mkdir -p "/home/ga/Documents/Surveillance_Reports"
chown -R ga:ga "/home/ga/Documents/Surveillance_Reports"

# ============================================================
# Create Bookmarks, Preferences, and Local State
# ============================================================
echo "Creating initial browser state (flat bookmarks, default settings)..."

python3 << 'PYEOF'
import json
import time
import os
import uuid

# Base Chrome timestamp (microseconds since 1601)
chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmark_data = [
    # Surveillance
    ("CDC Home", "https://www.cdc.gov/"),
    ("WHO Home", "https://www.who.int/"),
    ("ProMED-mail", "https://promedmail.org/"),
    ("HealthMap", "https://healthmap.org/"),
    ("ECDC", "https://www.ecdc.europa.eu/"),
    ("CDC FluView", "https://www.cdc.gov/flu/weekly/"),
    ("CDC ArboNET", "https://www.cdc.gov/arbonet/"),
    ("CDC NNDSS", "https://wonder.cdc.gov/"),
    # Databases
    ("GIDEON", "https://www.gideononline.com/"),
    ("PubMed", "https://pubmed.ncbi.nlm.nih.gov/"),
    ("CDC MMWR", "https://www.cdc.gov/mmwr/"),
    ("GenBank", "https://www.ncbi.nlm.nih.gov/genbank/"),
    ("BioPortal", "https://bioportal.bioontology.org/"),
    ("VAERS", "https://vaers.hhs.gov/"),
    # GIS
    ("ArcGIS Online", "https://www.arcgis.com/"),
    ("CDC Epi Info", "https://www.cdc.gov/epiinfo/"),
    ("Google Earth Engine", "https://earthengine.google.com/"),
    ("Census Geographies", "https://www.census.gov/geographies.html"),
    # Reporting
    ("NY State Health Dept", "https://www.health.ny.gov/"),
    ("CDC NBS", "https://www.cdc.gov/nbs/"),
    ("REDCap", "https://www.projectredcap.org/"),
    ("NSSP/BioSense", "https://www.syndromicsurveillance.org/"),
    # Personal
    ("YouTube", "https://www.youtube.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Weather", "https://weather.com/"),
    ("Wikipedia", "https://www.wikipedia.org/"),
    ("Gmail", "https://mail.google.com/")
]

children = []
for i, (name, url) in enumerate(bookmark_data):
    children.append({
        "date_added": str(chrome_base - (30 - i) * 60000000),
        "guid": str(uuid.uuid4()),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "initial_surveillance_state",
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

prefs = {
    "browser": {
        "show_home_button": True,
        "check_default_browser": False
    },
    "homepage": "https://www.google.com/",
    "homepage_is_newtabpage": False,
    "session": {
        "restore_on_startup": 5
    },
    "profile": {
        "password_manager_enabled": True,
        "cookie_controls_mode": 0
    },
    "download": {
        "default_directory": "/home/ga/Downloads",
        "prompt_for_download": False
    },
    "safebrowsing": {
        "enabled": True,
        "enhanced": False
    },
    "enable_do_not_track": False
}

local_state = {
    "browser": {
        "enabled_labs_experiments": []
    }
}

profile_dir = "/home/ga/.config/google-chrome-cdp/Default"
local_state_path = "/home/ga/.config/google-chrome-cdp/Local State"

os.makedirs(profile_dir, exist_ok=True)

with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=2)

with open(os.path.join(profile_dir, "Preferences"), "w") as f:
    json.dump(prefs, f, indent=2)

with open(local_state_path, "w") as f:
    json.dump(local_state, f, indent=2)
PYEOF

chown -R ga:ga "/home/ga/.config/google-chrome-cdp"

# Create standard instructions on Desktop
cat > /home/ga/Desktop/surveillance_workstation_standard.txt << 'EOF'
STATE DEPARTMENT OF HEALTH
Surveillance Workstation Configuration Standard v4.2

1. BOOKMARKS
All browsers must organize surveillance tools into exactly these 5 folders on the Bookmark Bar:
- Surveillance Feeds
- Disease Databases
- GIS & Mapping
- Reporting Tools
- Personal (Keep all personal sites isolated here)

2. SEARCH ENGINES
Add custom search engines to quickly access databases from the address bar:
- Keyword 'pub' -> PubMed
- Keyword 'mmwr' -> CDC MMWR
- Keyword 'epi' -> CDC Search

3. STARTUP & NAVIGATION
- Homepage: https://www.cdc.gov/
- Startup: Open exactly these 3 tabs on launch: cdc.gov, who.int, and promedmail.org

4. PRIVACY & SECURITY
- Block third-party cookies
- Enable "Do Not Track" requests
- Set Safe Browsing to "Enhanced Protection"
- Disable password saving (use the enterprise password manager instead)

5. PERFORMANCE FLAGS (chrome://flags)
- Enable "Parallel downloading" (crucial for large genomic datasets)
- Enable "Smooth Scrolling"

6. DOWNLOADS
- Default location: /home/ga/Documents/Surveillance_Reports
- MUST "Ask where to save each file before downloading"
EOF
chown ga:ga /home/ga/Desktop/surveillance_workstation_standard.txt

# Start Chrome via the environment's standard launch script
echo "Starting Chrome..."
su - ga -c "/home/ga/launch_chrome.sh > /dev/null 2>&1 &"
sleep 5

# Wait for Chrome window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        echo "Chrome window detected."
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="