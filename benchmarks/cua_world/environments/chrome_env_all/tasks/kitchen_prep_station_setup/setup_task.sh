#!/usr/bin/env bash
set -euo pipefail

echo "=== Kitchen Prep Station Task Setup ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create required directories
mkdir -p /home/ga/Documents/HACCP_Logs
chown -R ga:ga /home/ga/Documents

# 1. Kill any running Chrome to safely modify profile
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# 2. Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# 3. Create the specification document
cat > /home/ga/Desktop/prep_station_config.txt << 'EOF'
COMMERCIAL KITCHEN - PREP STATION IT REQUIREMENTS
Terminal ID: KITCH-PREP-01

Please optimize this browser for the kitchen staff:

1. BOOKMARKS ORGANIZATION
Create three active folders on the bookmark bar:
- "Recipes & Techniques" (All recipe, cooking, and food network sites)
- "Food Safety & HACCP" (All FDA, USDA, ServSafe, and safety guidelines)
- "Suppliers & Orders" (All purveyors: Sysco, US Foods, GFS, Baldor, etc.)

2. ARCHIVE CLUTTER
Create a folder named "Office_Archive" and move all non-kitchen, office, financial, and personal bookmarks into it.

3. ACCESSIBILITY
Cooks read this screen from the prep table (3-4 feet away). Change the browser Font Size to "Very Large".

4. SEARCH SHORTCUTS (Custom Search Engines)
Add the following site search shortcuts:
- Keyword: usda
  URL: https://fdc.nal.usda.gov/fdc-app.html#/?query=%s
- Keyword: recipe
  URL: https://www.seriouseats.com/search?q=%s

5. AUTOMATED DOWNLOADS
Temperature logs must download instantly without clicking popups.
- Change the default download location to: /home/ga/Documents/HACCP_Logs
- Toggle OFF the setting that asks where to save each file before downloading.

6. STARTUP PAGES
Set Chrome to "Open a specific page or set of pages" on startup:
- https://www.sysco.com
- https://www.servsafe.com
EOF

chown ga:ga /home/ga/Desktop/prep_station_config.txt

# 4. Generate Bookmarks and Default Preferences via Python
echo "Generating initial bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

culinary = [
    ("seriouseats.com", "Serious Eats"), ("chefsteps.com", "ChefSteps"), 
    ("epicurious.com", "Epicurious"), ("bonappetit.com", "Bon Appetit"),
    ("foodnetwork.com", "Food Network"), ("americastestkitchen.com", "America's Test Kitchen"),
    ("splendidtable.org", "Splendid Table"), ("saveur.com", "Saveur"),
    ("tastingtable.com", "Tasting Table"), ("thespruceeats.com", "The Spruce Eats")
]
safety = [
    ("fda.gov/food", "FDA Food Safety"), ("fsis.usda.gov", "USDA FSIS"),
    ("servsafe.com", "ServSafe"), ("foodsafety.gov", "FoodSafety.gov"),
    ("cdc.gov/foodsafety", "CDC Food Safety"), ("ecfr.gov", "Code of Federal Regulations")
]
suppliers = [
    ("sysco.com", "Sysco"), ("usfoods.com", "US Foods"), ("gfs.com", "Gordon Food Service"),
    ("baldorfood.com", "Baldor Specialty Foods"), ("restaurantequipment.com", "Restaurant Equipment")
]
office = [
    ("quickbooks.intuit.com", "QuickBooks Online"), ("adp.com", "ADP Payroll"),
    ("chase.com", "Chase Business Banking"), ("netflix.com", "Netflix"),
    ("facebook.com", "Facebook"), ("espn.com", "ESPN"), ("zillow.com", "Zillow"),
    ("amazon.com", "Amazon Prime"), ("target.com", "Target")
]

all_sites = culinary + safety + suppliers + office
# Shuffle slightly to make it unstructured
import random
random.seed(42)
random.shuffle(all_sites)

children = []
bid = 5

for i, (domain, name) in enumerate(all_sites):
    children.append({
        "date_added": str(chrome_base - (i * 600000000)),
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": f"https://www.{domain}/" if not domain.startswith("fda") and not domain.startswith("cdc") else f"https://www.{domain}"
    })
    bid += 1

bookmarks = {
    "checksum": "0",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(chrome_base), "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

profile_path = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_path, exist_ok=True)

with open(os.path.join(profile_path, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=4)

# Create non-compliant Preferences
prefs = {
    "browser": {"show_home_button": True, "check_default_browser": False},
    "download": {
        "default_directory": "/home/ga/Downloads",
        "prompt_for_download": True
    },
    "webkit": {
        "webprefs": {
            "default_font_size": 16
        }
    },
    "session": {
        "restore_on_startup": 1,
        "startup_urls": []
    }
}

with open(os.path.join(profile_path, "Preferences"), "w") as f:
    json.dump(prefs, f)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome/

# 5. Start Chrome 
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="