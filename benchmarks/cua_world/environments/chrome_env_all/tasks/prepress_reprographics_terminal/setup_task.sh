#!/usr/bin/env bash
set -euo pipefail

echo "=== Prepress Reprographics Terminal Task Setup ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Stop Chrome Safely to Modify Profile
echo "Stopping Chrome to set up task data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# 3. Create Required Directories
CHROME_DIR="/home/ga/.config/google-chrome"
CHROME_PROFILE="$CHROME_DIR/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/Prepress_Spool"
mkdir -p "/home/ga/Desktop"

# 4. Create Specification Document
cat > "/home/ga/Desktop/prepress_terminal_spec.txt" << 'SPEC_EOF'
PREPRESS TERMINAL BROWSER CONFIGURATION STANDARD
Version: 4.1.0

This shared terminal is used for downloading print-ready artwork and rendering 3D packaging proofs. Ensure the browser is strictly configured for production use.

1. FILE HANDLING (CRITICAL)
   - Chrome must NEVER open PDFs natively (it corrupts CMYK color rendering).
   - Go to Settings > Privacy and security > Site Settings > Additional content settings > PDF documents.
   - Set to "Download PDFs".

2. DOWNLOAD SPOOL
   - Default download location must be set to: /home/ga/Documents/Prepress_Spool
   - "Ask where to save each file before downloading" MUST be enabled.

3. HARDWARE ACCELERATION
   - Web-based 3D packaging proofers require forced GPU rasterization.
   - Go to chrome://flags
   - Enable "GPU rasterization" (#enable-gpu-rasterization)
   - Enable "Override software rendering list" (#ignore-gpu-blocklist)

4. COLOR SEARCH SHORTCUT
   - Add a custom site search in Settings > Search engine > Manage search engines and site search.
   - Keyword: color
   - URL: https://www.pantone.com/color-finder?q=%s

5. BOOKMARK ORGANIZATION
   - Organize existing professional bookmarks into 4 folders on the Bookmark Bar:
     * Web-to-Print MIS
     * Color Management
     * Asset Libraries
     * Equipment Support
   - REMOVE ALL PERSONAL BOOKMARKS. No Netflix, Facebook, ESPN, X/Twitter, or Hulu should remain anywhere in the browser.
SPEC_EOF

# 5. Generate Initial Bookmarks via Python
echo "Generating Bookmarks JSON..."
python3 << 'PYEOF'
import json
import time
import uuid

base_time = str((int(time.time()) + 11644473600) * 1000000)

bookmarks_list = [
    # MIS
    ("EFI", "https://www.efi.com/"), 
    ("Fiery", "https://www.fiery.com/"), 
    ("Pressero", "https://www.pressero.com/"), 
    ("HP PrintOS", "https://www.printos.com/"), 
    ("Heidelberg", "https://www.heidelberg.com/"),
    # Color
    ("Pantone", "https://www.pantone.com/"), 
    ("X-Rite", "https://www.xrite.com/"), 
    ("Fogra", "https://www.fogra.org/"), 
    ("ICC", "https://www.color.org/"), 
    ("basICColor", "https://www.basiccolor.de/"),
    # Assets
    ("Shutterstock", "https://www.shutterstock.com/"), 
    ("Getty Images", "https://www.gettyimages.com/"), 
    ("Adobe Stock", "https://stock.adobe.com/"), 
    ("Freepik", "https://www.freepik.com/"),
    # Equip
    ("HP Support", "https://support.hp.com/"), 
    ("Canon Support", "https://www.usa.canon.com/support"), 
    ("Ricoh Support", "https://www.ricoh.com/support"), 
    ("Epson Support", "https://epson.com/support"),
    # Personal
    ("Netflix", "https://www.netflix.com/"), 
    ("Facebook", "https://www.facebook.com/"), 
    ("ESPN", "https://www.espn.com/"), 
    ("X (Twitter)", "https://twitter.com/"), 
    ("Hulu", "https://www.hulu.com/")
]

children = []
for i, (name, url) in enumerate(bookmarks_list):
    children.append({
        "date_added": base_time,
        "guid": str(uuid.uuid4()),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": base_time,
            "date_modified": base_time,
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
        "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

# Fix Permissions
chown -R ga:ga /home/ga/.config/google-chrome/
chown ga:ga /home/ga/Desktop/prepress_terminal_spec.txt

# 6. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check --remote-debugging-port=9222 &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="