#!/bin/bash
set -euo pipefail

echo "=== Setting up Genealogy Reading Room Terminal Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop any running Chrome instances
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true

# Prepare Chrome directory
CHROME_DIR="/home/ga/.config/google-chrome"
PROFILE_DIR="$CHROME_DIR/Default"
mkdir -p "$PROFILE_DIR"

# Create target download directory
mkdir -p "/home/ga/Documents/Archive_Downloads"

# Create the specification file
cat > "/home/ga/Desktop/reading_room_spec.txt" << 'SPEC_EOF'
GENEALOGY READING ROOM - TERMINAL CONFIGURATION STANDARD v2.4

This workstation is used by elderly researchers to access historical databases and download large microfiche/census scans. Please configure Chrome as follows:

1. BOOKMARKS
   - Create three folders on the Bookmark Bar: "Federal & State Archives", "Vital Records", and "Volunteer Personal".
   - Sort the existing bookmarks into their appropriate folders.
   - Any non-research, personal, or entertainment sites (like Facebook, Netflix, etc.) MUST be isolated into the "Volunteer Personal" folder.

2. CUSTOM SEARCH ENGINES (Navigate to chrome://settings/searchEngines)
   Add the following shortcuts:
   - Library of Congress: Keyword 'loc', URL 'https://www.loc.gov/search/?q=%s'
   - National Archives: Keyword 'nara', URL 'https://catalog.archives.gov/search?q=%s'
   - Find a Grave: Keyword 'fag', URL 'https://www.findagrave.com/memorial/search?lastname=%s'

3. CHROME FLAGS (Navigate to chrome://flags)
   Enable the following features to optimize for reading long microfilm reels and downloading massive TIFF images:
   - "Parallel downloading"
   - "Smooth Scrolling"
   - "Back-forward cache"

4. ACCESSIBILITY (Navigate to Appearance settings)
   - Set the Minimum font size to 16
   - Set the Default font size to 22

5. BULK DOWNLOADS (Navigate to Download settings)
   - Set the default download location to: /home/ga/Documents/Archive_Downloads
   - Turn OFF "Ask where to save each file before downloading"

6. TERMINAL PRIVACY (Navigate to Autofill and passwords)
   To protect public users, disable:
   - Offer to save passwords
   - Save and fill addresses
   - Save and fill payment methods
SPEC_EOF
chown ga:ga "/home/ga/Desktop/reading_room_spec.txt"

# Create initial bookmarks (Flat structure)
echo "Creating initial bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

base_time = (int(time.time()) + 11644473600) * 1000000

sites = [
    ("National Archives", "https://catalog.archives.gov"),
    ("Library of Congress", "https://www.loc.gov"),
    ("DPLA", "https://dp.la"),
    ("NY State Archives", "https://archives.ny.gov"),
    ("Calisphere", "https://calisphere.org"),
    ("FamilySearch", "https://www.familysearch.org"),
    ("Ancestry", "https://www.ancestry.com"),
    ("Find A Grave", "https://www.findagrave.com"),
    ("Ellis Island Records", "https://www.ellisisland.org"),
    ("Fold3 Military Records", "https://www.fold3.com"),
    ("Facebook", "https://www.facebook.com"),
    ("Pinterest", "https://www.pinterest.com"),
    ("YouTube", "https://www.youtube.com"),
    ("Etsy", "https://www.etsy.com"),
    ("Netflix", "https://www.netflix.com"),
    ("Instagram", "https://www.instagram.com"),
    ("Hulu", "https://www.hulu.com"),
    ("Spotify", "https://www.spotify.com")
]

children = []
for i, (name, url) in enumerate(sites):
    children.append({
        "date_added": str(base_time - i * 1000000),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(base_time),
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
        "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown -R ga:ga "$CHROME_DIR"

# Launch Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check >/dev/null 2>&1 &"
sleep 4

# Wait for Chrome window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Chrome"; then
        break
    fi
    sleep 1
done

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Give time for rendering
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="