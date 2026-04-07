#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Agricultural Extension Browser Setup Task ==="
date +%s > /tmp/task_start_time.txt

# Create necessary directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Documents/Extension_Bulletins
CHROME_DIR="/home/ga/.config/google-chrome"
PROFILE_DIR="$CHROME_DIR/Default"
mkdir -p "$PROFILE_DIR"

# Write the specification file
cat > /home/ga/Desktop/extension_workspace_standard.txt << 'EOF'
STATE COOPERATIVE EXTENSION SERVICE
Digital Workspace Standard CES-DWS-2025-01
Applies to: All County Extension Office Workstations

1. BOOKMARK ORGANIZATION
All bookmarks must be organized into four specific folders on the Bookmark Bar:
- "Crop Science": For agronomy, soils, crops, weather, and pest management.
- "Livestock & Veterinary": For animal health, beef/pork boards, and inspection.
- "Extension Programs": For 4-H, Master Gardener, FFA, NIFA, and general extension resources.
- "Personal": For any non-work related sites (email, shopping, entertainment, general news).
No bookmarks should remain loose on the bookmark bar.

2. PERFORMANCE OPTIMIZATION (Flags)
Due to aging office hardware, configure the following via chrome://flags:
- Enable Smooth Scrolling
- Enable Parallel downloading
- Enable Back-forward cache

3. PRESENTATION ACCESSIBILITY (Fonts)
Agents regularly project screens. Navigate to chrome://settings/fonts and set:
- Default font size: 20
- Fixed-width font size: 18
- Minimum font size: 14

4. SEARCH SHORTCUTS
Add the following custom search engines:
- Keyword: usda | URL: https://search.usa.gov/search?affiliate=usda&query=%s
- Keyword: ext  | URL: https://search.extension.org/search?q=%s

5. STARTUP AND HOMEPAGE
- Set Homepage to: https://www.nifa.usda.gov
- Set Startup behavior to open specific pages:
  1) https://www.nifa.usda.gov
  2) https://www.ers.usda.gov

6. DOWNLOADS & SECURITY
- Default download location must be: /home/ga/Documents/Extension_Bulletins
- Enable "Ask where to save each file before downloading"
- Disable "Offer to save passwords"
- Disable "Save and fill addresses"
- Disable "Save and fill payment methods"
EOF

# Stop Chrome to safely write profiles
pkill -9 -f chrome 2>/dev/null || true
sleep 1

# Generate Chrome data via Python
python3 - << 'PYEOF'
import json, os, uuid, time

profile_dir = "/home/ga/.config/google-chrome/Default"
chrome_dir = "/home/ga/.config/google-chrome"
os.makedirs(profile_dir, exist_ok=True)

# 1. Generate Bookmarks
urls = [
    # Crop
    ("https://plants.usda.gov", "USDA PLANTS Database"),
    ("https://www.nass.usda.gov", "USDA NASS"),
    ("https://www.ers.usda.gov", "USDA ERS"),
    ("https://www.crops.org", "Crop Science Society"),
    ("https://extension.org/crops", "Extension Crops"),
    ("https://www.nrcs.usda.gov", "USDA NRCS"),
    ("https://www.weather.gov/agriculture", "Ag Weather"),
    ("https://ipm.ucanr.edu", "UC IPM"),
    # Livestock
    ("https://www.aphis.usda.gov", "USDA APHIS"),
    ("https://www.nahln.org", "NAHLN"),
    ("https://www.beefresearch.org", "Beef Research"),
    ("https://www.pork.org", "National Pork Board"),
    ("https://www.avma.org", "AVMA"),
    ("https://extension.org/animals", "Extension Animals"),
    ("https://www.fsis.usda.gov", "USDA FSIS"),
    # Extension
    ("https://www.nifa.usda.gov", "USDA NIFA"),
    ("https://extension.org", "Cooperative Extension"),
    ("https://4-h.org", "National 4-H"),
    ("https://www.fsa.usda.gov", "USDA FSA"),
    ("https://www.rd.usda.gov", "USDA Rural Dev"),
    ("https://mastergardener.extension.org", "Master Gardener"),
    ("https://www.ffa.org", "National FFA"),
    # Personal
    ("https://www.youtube.com", "YouTube"),
    ("https://www.amazon.com", "Amazon"),
    ("https://www.espn.com", "ESPN"),
    ("https://mail.google.com", "Gmail"),
    ("https://www.facebook.com", "Facebook"),
    ("https://www.netflix.com", "Netflix"),
    ("https://www.weather.com", "Weather Channel")
]

children = []
chrome_base_time = str((int(time.time()) + 11644473600) * 1000000)
for i, (url, name) in enumerate(urls):
    children.append({
        "date_added": chrome_base_time,
        "guid": str(uuid.uuid4()),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": chrome_base_time, "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": chrome_base_time, "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": chrome_base_time, "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f)

# 2. Generate Preferences (bad defaults)
prefs = {
    "homepage": "https://www.google.com",
    "homepage_is_newtabpage": False,
    "session": {
        "restore_on_startup": 5,
        "startup_urls": []
    },
    "webkit": {
        "webprefs": {
            "default_font_size": 16,
            "default_fixed_font_size": 13,
            "minimum_font_size": 0
        }
    },
    "download": {
        "default_directory": "/home/ga/Downloads",
        "prompt_for_download": False
    },
    "profile": {
        "password_manager_enabled": True
    },
    "autofill": {
        "profile_enabled": True,
        "credit_card_enabled": True
    }
}

with open(os.path.join(profile_dir, "Preferences"), "w") as f:
    json.dump(prefs, f)

# 3. Generate Local State (no flags)
local_state = {
    "browser": {
        "enabled_labs_experiments": []
    }
}

with open(os.path.join(chrome_dir, "Local State"), "w") as f:
    json.dump(local_state, f)
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/.config/google-chrome
chown -R ga:ga /home/ga/Desktop
chown -R ga:ga /home/ga/Documents

# Launch Chrome
su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --disable-dev-shm-usage &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="