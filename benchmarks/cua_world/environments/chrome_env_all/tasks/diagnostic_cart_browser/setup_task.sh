#!/bin/bash
echo "=== Setting up Diagnostic Cart Browser Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create required download directory
mkdir -p /home/ga/Documents/TSB_Wiring_Diagrams
chown ga:ga /home/ga/Documents/TSB_Wiring_Diagrams

# Stop Chrome to safely prepare profile data
echo "Stopping Chrome to inject bookmarks..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome

# Create the spec guide on the Desktop
cat > /home/ga/Desktop/cart_setup_guide.txt << 'EOF'
DIAGNOSTIC CART BROWSER CONFIGURATION GUIDE
-------------------------------------------
1. BOOKMARKS:
   Delete all personal bookmarks.
   Create exactly 4 folders on the bookmark bar and categorize the work sites:
     - "OEM Portals": techauthority.com, acdelcotds.com, motorcraftservice.com, techinfo.honda.com, techinfo.toyota.com
     - "Parts Suppliers": rockauto.com, napaonline.com, autozonepro.com, oreillyauto.com, fcp-euro.com
     - "Diagnostic Tools": alldata.com, prodemand.com, identifix.com, iatn.net
     - "Shop Management": shop-monkey.com, mitchell1.com, partslogistics.com, motor.com

2. POPUP EXCEPTIONS (Settings > Privacy and security > Site Settings > Pop-ups and redirects):
   Add explicitly "Allowed" exceptions for:
     - [*.]motorcraftservice.com
     - [*.]acdelcotds.com
     - [*.]techauthority.com

3. VIN SEARCH ENGINE (Settings > Search engine > Manage search engines):
   Add a site search shortcut:
     - Name: NHTSA VIN Decoder
     - Shortcut/Keyword: vin
     - URL: https://vpic.nhtsa.dot.gov/decoder/Decoder/Submit/VIN?VIN=%s

4. VISIBILITY (Settings > Appearance):
   - Page zoom: 125%

5. DOWNLOADS (Settings > Downloads):
   - Location: /home/ga/Documents/TSB_Wiring_Diagrams
   - Ask where to save each file before downloading: OFF
EOF
chown ga:ga /home/ga/Desktop/cart_setup_guide.txt

# Create Bookmarks JSON via Python to ensure valid formatting
python3 << 'PYEOF'
import json
import time

base_time = str((int(time.time()) + 11644473600) * 1000000)

bookmarks_list = [
    ("TechAuthority", "https://www.techauthority.com"),
    ("ACDelco TDS", "https://www.acdelcotds.com"),
    ("Motorcraft Service", "https://www.motorcraftservice.com"),
    ("Honda Service", "https://techinfo.honda.com"),
    ("Toyota TIS", "https://techinfo.toyota.com"),
    ("RockAuto", "https://www.rockauto.com"),
    ("NAPA PRO", "https://www.napaonline.com"),
    ("AutoZone Pro", "https://www.autozonepro.com"),
    ("O'Reilly First Call", "https://firstcall.oreillyauto.com"),
    ("FCP Euro", "https://www.fcp-euro.com"),
    ("ALLDATA", "https://www.alldata.com"),
    ("ProDemand", "https://www.prodemand.com"),
    ("Identifix", "https://www.identifix.com"),
    ("iATN", "https://www.iatn.net"),
    ("Shopmonkey", "https://www.shop-monkey.com"),
    ("Mitchell 1", "https://mitchell1.com/manage"),
    ("Parts Logistics", "https://www.partslogistics.com"),
    ("MOTOR", "https://www.motor.com"),
    ("Netflix", "https://www.netflix.com"),
    ("Facebook", "https://www.facebook.com"),
    ("ESPN Fantasy", "https://fantasy.espn.com"),
    ("Reddit", "https://www.reddit.com"),
    ("Steam", "https://store.steampowered.com"),
    ("Twitter", "https://twitter.com")
]

children = []
for i, (name, url) in enumerate(bookmarks_list):
    children.append({
        "date_added": str(int(base_time) - i * 1000000),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_obj = {
    "checksum": "00000000000000000000000000000000",
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
    json.dump(bookmarks_obj, f, indent=3)
PYEOF
chown ga:ga /home/ga/.config/google-chrome/Default/Bookmarks

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --restore-last-session > /dev/null 2>&1 &"
sleep 5

# Wait for Chrome window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        break
    fi
    sleep 1
done

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="