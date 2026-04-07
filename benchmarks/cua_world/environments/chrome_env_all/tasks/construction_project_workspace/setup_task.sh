#!/bin/bash
set -euo pipefail

echo "=== Setting up construction_project_workspace task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Documents/Summit_Crossing/Downloads
chown -R ga:ga /home/ga/Documents/Summit_Crossing

# Stop any running Chrome instances to safely modify profile
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chromium" 2>/dev/null || true
sleep 2

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# 1. Generate Initial Bookmarks via Python
echo "Generating initial flat bookmarks..."
python3 << 'PYEOF'
import json
import time
import uuid
import os

chrome_base = (int(time.time()) + 11644473600) * 1000000

# Bookmarks Definition
rc_bookmarks = [
    ("[RC] Procore Project Dashboard", "https://app.procore.com/projects/riverside-commons"),
    ("[RC] City Permits Portal", "https://permit.city.gov/rc-permits"),
    ("[RC] Geotech Report", "https://drive.google.com/rc-geotech"),
    ("[RC] Structural Plans", "https://drive.google.com/rc-structural"),
    ("[RC] MEP Drawings", "https://drive.google.com/rc-mep"),
    ("[RC] Phase 2 Schedule", "https://app.smartsheet.com/b/rc-schedule"),
    ("[RC] Punchlist Tracker", "https://app.plangrid.com/rc-punch"),
    ("[RC] Final Inspection Checklist", "https://studio.bluebeam.com/rc-final")
]

industry_bookmarks = [
    ("ICC Digital Codes", "https://codes.iccsafe.org/"),
    ("NFPA Codes & Standards", "https://www.nfpa.org/"),
    ("ASTM International", "https://www.astm.org/"),
    ("ACI Concrete Standards", "https://www.concrete.org/"),
    ("AISC Steel Construction", "https://www.aisc.org/"),
    ("OSHA Home", "https://www.osha.gov/"),
    ("OSHA 1926 Construction", "https://www.osha.gov/laws-regs/regulations/standardnumber/1926"),
    ("CPWR Safety Research", "https://www.cpwr.com/"),
    ("Procore Login", "https://app.procore.com/"),
    ("Autodesk Construction Cloud", "https://construction.autodesk.com/"),
    ("Bluebeam Studio", "https://studio.bluebeam.com/"),
    ("Smartsheet", "https://app.smartsheet.com/"),
    ("Grainger Industrial Supply", "https://www.grainger.com/"),
    ("Fastenal", "https://www.fastenal.com/"),
    ("McMaster-Carr", "https://www.mcmaster.com/"),
    ("NWS Weather", "https://www.weather.gov/"),
    ("Weather Underground", "https://www.wunderground.com/"),
    ("United Rentals", "https://www.unitedrentals.com/"),
    ("Sunbelt Rentals", "https://www.sunbeltrentals.com/"),
    ("Caterpillar", "https://www.cat.com/")
]

personal_bookmarks = [
    ("ESPN", "https://www.espn.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("NFL", "https://www.nfl.com/"),
    ("Bass Pro Shops", "https://www.basspro.com/"),
    ("Home Depot", "https://www.homedepot.com/"),
    ("Zillow", "https://www.zillow.com/"),
    ("Bank of America", "https://www.bankofamerica.com/"),
    ("Gmail", "https://mail.google.com/"),
    ("Facebook", "https://www.facebook.com/")
]

all_bookmarks = rc_bookmarks + industry_bookmarks + personal_bookmarks

children = []
for i, (name, url) in enumerate(all_bookmarks):
    ts = str(chrome_base - (50 - i) * 600000000)
    children.append({
        "date_added": ts,
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_obj = {
    "checksum": "initial_construction_workspace_00",
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

profile_path = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_path, exist_ok=True)
with open(os.path.join(profile_path, "Bookmarks"), "w", encoding="utf-8") as f:
    json.dump(bookmarks_obj, f, indent=3)

# Save a copy for anti-gaming verification
with open("/tmp/initial_bookmarks.json", "w", encoding="utf-8") as f:
    json.dump(bookmarks_obj, f, indent=3)
PYEOF

# 2. Generate Non-Compliant Preferences
echo "Generating non-compliant preferences..."
cat > "$CHROME_PROFILE/Preferences" << 'PREF_EOF'
{
  "browser": {
    "show_home_button": true,
    "check_default_browser": false
  },
  "homepage": "https://www.google.com",
  "homepage_is_newtabpage": false,
  "download": {
    "default_directory": "/home/ga/Downloads",
    "prompt_for_download": false
  },
  "profile": {
    "cookie_controls_mode": 0,
    "password_manager_enabled": true
  },
  "credentials_enable_service": true,
  "autofill": {
    "profile_enabled": true
  }
}
PREF_EOF
chown -R ga:ga /home/ga/.config/google-chrome

# 3. Create the Specification Document
echo "Writing Specification Document..."
cat > "/home/ga/Desktop/project_browser_spec.txt" << 'SPEC_EOF'
MERIDIAN CONSTRUCTION GROUP - IT POLICY
Jobsite Browser Configuration Standard (Rev 4.2)
Project: Summit Crossing

1. BOOKMARKS
- Create a "Summit Crossing Project" folder on the bookmark bar with the following subfolders: Codes & Standards, Safety & Compliance, Project Management, Materials & Suppliers, Weather & Conditions, Equipment & Rentals.
- Move relevant active construction bookmarks into these exact subfolders.
- Create an "Archived - Riverside Commons" folder and move all [RC] tagged bookmarks here.
- Create a "Personal" folder and move all non-work sites here to keep the main view professional.

2. SEARCH ENGINES
Configure the following site search shortcuts (manage search engines):
- Keyword: icc -> URL: https://codes.iccsafe.org/search?q=%s
- Keyword: osha -> URL: https://www.osha.gov/search?q=%s
- Keyword: msds -> URL: https://www.msds.com/?q=%s

3. HOMEPAGE & STARTUP
- Homepage: https://app.procore.com
- Startup: Open specific pages (procore.com and weather.gov)

4. DOWNLOADS
- Default Location: /home/ga/Documents/Summit_Crossing/Downloads
- Enable "Ask where to save each file before downloading"

5. PRIVACY & SECURITY
- Block third-party cookies
- Disable password saving
- Disable address and payment autofill

6. SITE PERMISSIONS
- Allow Notifications for: procore.com and smartsheet.com
SPEC_EOF
chown ga:ga "/home/ga/Desktop/project_browser_spec.txt"

# 4. Launch Chrome
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --no-first-run > /dev/null 2>&1 &"

# Wait for Chrome window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        break
    fi
    sleep 1
done

# Maximize the Chrome window
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Give UI time to settle
sleep 2

# Take initial screenshot for verification evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Task setup complete ==="