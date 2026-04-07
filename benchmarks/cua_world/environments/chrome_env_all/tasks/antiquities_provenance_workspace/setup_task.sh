#!/usr/bin/env bash
set -euo pipefail

echo "=== Antiquities Provenance Workspace Task Setup ==="
echo "Task: Configure browser per Appraiser Browser Spec"

sleep 2
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Create the required download directory
mkdir -p "/home/ga/Documents/Auction_Catalog_Assets"
chown ga:ga "/home/ga/Documents/Auction_Catalog_Assets"

# Create the spec file
cat > "/home/ga/Desktop/appraiser_browser_spec.txt" << 'EOF'
APPRAISER BROWSER CONFIGURATION SPECIFICATION v2.1

1. BOOKMARK ORGANIZATION
Create four folders on the Bookmark Bar and move the relevant URLs into them:
- "Provenance & Stolen Art": FBI Art Theft, Interpol, Art Loss Register, LootedArt
- "Museum Archives": Metropolitan Museum, Getty, British Museum, Louvre
- "Auction Records": Artnet, Sotheby's, Christie's, Artsy, MutualArt
- "Internal Admin": Gmail, Workday, DocuSign

2. DATA PURGING
Delete all non-compliant personal bookmarks from the browser (Netflix, ESPN, Facebook, Hulu). They must not exist anywhere in the bookmark tree.

3. STARTUP BEHAVIOR
Configure Chrome to automatically open these two specific pages on startup:
- https://www.artloss.com/
- https://www.artnet.com/

4. SITE PERMISSIONS
- Pop-ups & Redirects: Allow specifically for "artnet.com" and "metmuseum.org" to support their high-resolution image viewer windows.
- Notifications: Block globally.

5. TYPOGRAPHY & ACCESSIBILITY
To reduce eye strain when reading historical documents:
- Medium (Default) font size: 18
- Minimum font size: 14

6. DOWNLOAD MANAGEMENT
- Default download location: /home/ga/Documents/Auction_Catalog_Assets
- Enable the prompt: "Ask where to save each file before downloading"
EOF
chown ga:ga "/home/ga/Desktop/appraiser_browser_spec.txt"

# Create Chrome profile
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# Create Bookmarks JSON with flat mixed data
python3 << 'PYEOF'
import json, time, uuid

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks = [
    # Provenance
    ("FBI Art Theft", "https://www.fbi.gov/investigate/violent-crime/art-theft"),
    ("Interpol", "https://www.interpol.int/Crimes/Illicit-goods/Stolen-works-of-art"),
    ("Art Loss Register", "https://www.artloss.com/"),
    ("LootedArt", "https://www.lootedart.com/"),
    # Museums
    ("Metropolitan Museum", "https://www.metmuseum.org/"),
    ("Getty", "https://www.getty.edu/"),
    ("British Museum", "https://www.britishmuseum.org/"),
    ("Louvre", "https://www.louvre.fr/"),
    # Auction
    ("Artnet", "https://www.artnet.com/"),
    ("Sotheby's", "https://www.sothebys.com/"),
    ("Christie's", "https://www.christies.com/"),
    ("Artsy", "https://www.artsy.net/"),
    ("MutualArt", "https://www.mutualart.com/"),
    # Admin
    ("Gmail", "https://mail.google.com/"),
    ("Workday", "https://www.workday.com/"),
    ("DocuSign", "https://www.docusign.com/"),
    # Personal (to be purged)
    ("Netflix", "https://www.netflix.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Hulu", "https://www.hulu.com/")
]

children = []
bid = 5

for i, (name, url) in enumerate(bookmarks):
    ts = str(chrome_base - (i + 1) * 600000000)
    children.append({
        "date_added": ts,
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": url
    })
    bid += 1

bookmarks_data = {
    "checksum": "0" * 32,
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

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks_data, f, indent=3)
PYEOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Remove any existing Preferences to start clean
rm -f "$CHROME_PROFILE/Preferences"

date +%s > /tmp/task_start_time.txt
echo "=== Task Setup Complete ==="