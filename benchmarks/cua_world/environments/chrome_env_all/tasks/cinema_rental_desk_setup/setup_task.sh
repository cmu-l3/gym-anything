#!/bin/bash
set -euo pipefail

echo "=== Setting up cinema_rental_desk_setup task ==="

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/Invoices
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Documents /home/ga/Desktop

# Create the specification file
cat > /home/ga/Desktop/checkout_terminal_standard.txt << 'EOF'
SILVER SCREEN RENTALS - CHECKOUT TERMINAL BROWSER CONFIGURATION STANDARD

1. BOOKMARK ORGANIZATION
   Create the following folders on the bookmark bar and sort existing work links into them:
   - "Inventory" (rentman.io, booqable.com, ezrentout.com, cheqroom.com)
   - "Camera Manuals" (arri.com, red.com, sonycine.com, usa.canon.com, panavision.com)
   - "Insurance" (insuremyequipment.com, thehartford.com, frontline.com, thimble.com)
   - "Logistics" (fedex.com, ups.com, dhl.com, usps.com)

2. DATA SANITIZATION
   - Completely delete/remove all personal bookmarks left by the weekend freelancer (Facebook, Twitter, ESPN, Netflix, Spotify, Reddit, YouTube, Amazon).

3. POP-UPS & NOTIFICATIONS
   - Pop-ups: Blocked globally, but add an exception to ALLOW pop-ups for "rentman.io" (required for rental agreements).
   - Notifications: Set to "Don't allow sites to send notifications" (Block all).

4. PRIVACY & CREDENTIALS (CRITICAL FOR SHARED TERMINAL)
   - Disable "Offer to save passwords"
   - Disable "Auto Sign-in"
   - Disable saving and filling payment methods
   - Disable saving and filling addresses

5. WORKFLOW AUTOMATION (DOWNLOADS & STARTUP)
   - Download Location: Change to "/home/ga/Documents/Invoices"
   - Download Prompt: Turn OFF "Ask where to save each file before downloading" (invoices must download silently).
   - Startup: Configure Chrome to open a specific page on startup: "https://rentman.io/login".
EOF
chown ga:ga /home/ga/Desktop/checkout_terminal_standard.txt

# Stop any running Chrome instances
echo "Stopping Chrome to modify profile safely..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# Generate Bookmarks and Preferences via Python to ensure valid JSON
python3 << 'PYEOF'
import json
import time
import os

profile_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_dir, exist_ok=True)

# 1. Create Bookmarks
work_bms = [
    ("Rentman", "https://rentman.io/login"), ("Booqable", "https://booqable.com/"), 
    ("EZRentOut", "https://ezrentout.com/"), ("Cheqroom", "https://cheqroom.com/"),
    ("ARRI Support", "https://www.arri.com/en/learn-help"), ("RED Manuals", "https://www.red.com/downloads"),
    ("Sony Cine", "https://sonycine.com/"), ("Canon Support", "https://usa.canon.com/support"), 
    ("Panavision", "https://www.panavision.com/"),
    ("InsureMyEquipment", "https://insuremyequipment.com/"), ("The Hartford", "https://www.thehartford.com/"),
    ("Frontline", "https://frontline.com/"), ("Thimble", "https://www.thimble.com/"),
    ("FedEx", "https://www.fedex.com/"), ("UPS", "https://www.ups.com/"), 
    ("DHL", "https://www.dhl.com/"), ("USPS", "https://www.usps.com/")
]
personal_bms = [
    ("Facebook", "https://www.facebook.com/"), ("Twitter", "https://twitter.com/"), 
    ("ESPN", "https://www.espn.com/"), ("Netflix", "https://www.netflix.com/"),
    ("Spotify", "https://open.spotify.com/"), ("Reddit", "https://www.reddit.com/"), 
    ("YouTube", "https://www.youtube.com/"), ("Amazon", "https://www.amazon.com/")
]

children = []
base_ts = str((int(time.time()) + 11644473600) * 1000000)

all_bms = work_bms + personal_bms
# Interleave them slightly
import random
random.seed(42)
random.shuffle(all_bms)

for i, (name, url) in enumerate(all_bms):
    children.append({
        "date_added": str(int(base_ts) - i * 1000000),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "00000000000000000000000000000000",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": base_ts,
            "date_modified": base_ts,
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
        "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
    },
    "version": 1
}

with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)

# 2. Create Default Preferences (Intentionally NON-COMPLIANT)
prefs = {
    "profile": {
        "password_manager_enabled": True,
        "default_content_setting_values": {
            "notifications": 3, 
            "popups": 2 
        },
        "content_settings": {
            "exceptions": {
                "popups": {}
            }
        }
    },
    "credentials_enable_service": True,
    "autofill": {
        "profile_enabled": True,
        "credit_card_enabled": True
    },
    "download": {
        "default_directory": "/home/ga/Downloads",
        "prompt_for_download": True
    },
    "session": {
        "restore_on_startup": 5, 
        "startup_urls": []
    }
}

with open(os.path.join(profile_dir, "Preferences"), "w") as f:
    json.dump(prefs, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome

# Start Chrome (via launch script or directly)
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /usr/bin/google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Initial Screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="