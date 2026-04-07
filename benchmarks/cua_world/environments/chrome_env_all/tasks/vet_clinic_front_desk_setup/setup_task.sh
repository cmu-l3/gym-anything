#!/usr/bin/env bash
set -euo pipefail

echo "=== Vet Clinic Front Desk Setup Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Stop Chrome to safely modify profile data
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
pkill -f "google-chrome" 2>/dev/null || true
sleep 2

# Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# Generate the clinic protocol text file
cat > /home/ga/Desktop/clinic_browser_protocol.txt << 'EOF'
PAWS & CLAWS ANIMAL HOSPITAL - IT PROTOCOL
Front Desk Workstation Browser Configuration v2.1

1. BOOKMARK ORGANIZATION
All bookmarks must be organized into exactly 5 folders on the bookmark bar. No loose bookmarks should remain on the bar.
- "Practice & Labs": ezyVet, IDEXX (VetConnect), Antech, Zoetis
- "Suppliers & Diets": Covetrus, MWI, Patterson, Hills, Royal Canin, Purina
- "Client Finance": CareCredit, Scratchpay, Trupanion
- "Medical Reference": Plumb's, Merck Vet Manual, ASPCA Poison Control
- "Industry Org": AVMA, AAHA

2. PERSONAL CLUTTER
Remove ANY non-work/personal bookmarks from the browser completely (e.g., Netflix, Facebook, Pinterest, Spotify, Amazon, Zillow).

3. SEARCH SHORTCUTS
Create two custom search engines (Settings > Search engine > Manage search engines and site search):
- Keyword "plumbs" pointing to Plumb's Veterinary Drugs
- Keyword "merck" pointing to Merck Veterinary Manual

4. SITE SETTINGS (CRITICAL FOR WORKFLOW)
Navigate to Chrome Site Settings and enforce these policies:
- PDFs: Set to "Download PDFs" (do NOT open in Chrome - we need them downloaded to attach to the PMS)
- Notifications: Set to "Don't allow sites to send notifications"
- Sound: Set to "Mute sites that play sound" (to avoid startling animals or clients at the desk)

5. STARTUP PAGES
Set the browser to "Open a specific page or set of pages" on startup:
- https://www.ezyvet.com
- https://www.vetconnectplus.com
EOF

chown ga:ga /home/ga/Desktop/clinic_browser_protocol.txt

# Create initial Bookmarks JSON using Python
python3 << 'PYEOF'
import json, time, uuid, os

chrome_profile = "/home/ga/.config/google-chrome/Default"
os.makedirs(chrome_profile, exist_ok=True)

chrome_base = (int(time.time()) + 11644473600) * 1000000

# Mix of vet bookmarks and personal clutter
urls = [
    ("ezyVet", "https://www.ezyvet.com"),
    ("Netflix", "https://www.netflix.com"),
    ("IDEXX VetConnect", "https://www.vetconnectplus.com"),
    ("Antech Diagnostics", "https://www.antechdiagnostics.com"),
    ("Facebook", "https://www.facebook.com"),
    ("Zoetis", "https://www.zoetis.com/vets"),
    ("Covetrus", "https://www.covetrus.com"),
    ("Pinterest", "https://www.pinterest.com"),
    ("MWI Animal Health", "https://www.mwiah.com"),
    ("Patterson Vet", "https://www.pattersonvet.com"),
    ("Spotify", "https://www.spotify.com"),
    ("CareCredit Vet", "https://www.carecredit.com/vet"),
    ("Scratchpay", "https://www.scratchpay.com"),
    ("Trupanion", "https://www.trupanion.com/vets"),
    ("Amazon", "https://www.amazon.com"),
    ("Plumb's Vet Drugs", "https://www.plumbs.com"),
    ("Merck Vet Manual", "https://www.merckvetmanual.com"),
    ("ASPCA Poison Control", "https://www.aspca.org/pet-care/animal-poison-control"),
    ("Zillow", "https://www.zillow.com"),
    ("AVMA", "https://www.avma.org"),
    ("AAHA", "https://www.aaha.org"),
    ("Hills Pet Nutrition", "https://www.hillspet.com/vets"),
    ("Royal Canin Vets", "https://www.royalcanin.com/vets"),
    ("Purina Pro Club", "https://www.purinaproclub.com")
]

children = []
for i, (name, url) in enumerate(urls):
    children.append({
        "date_added": str(chrome_base - (i * 600000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "initial_state",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": str(chrome_base),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
        "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
    },
    "version": 1
}

with open(os.path.join(chrome_profile, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome

# Start Chrome in the background
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable > /tmp/chrome.log 2>&1 &"
sleep 5

# Focus and maximize window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take an initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="