#!/bin/bash
set -euo pipefail
echo "=== Setup Brewhouse Control Terminal Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Terminate Chrome to safely inject profile files
pkill -f "chrome" 2>/dev/null || true
sleep 2

# Create directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

mkdir -p /home/ga/Documents/Batch_Logs
chown -R ga:ga /home/ga/Documents

# Use Python to generate Bookmarks payload to ensure well-formed JSON
python3 << 'EOF'
import json, time, uuid, os, sqlite3

chrome_base = (int(time.time()) + 11644473600) * 1000000

urls = [
    ("https://www.ttb.gov", "TTB Home"),
    ("https://www.ttbonline.gov", "TTB Online"),
    ("https://www.ttb.gov/beer/laws-regulations", "TTB Beer Laws"),
    ("https://www.asbcnet.org", "ASBC"),
    ("https://www.mbaa.com", "MBAA"),
    ("https://www.whitelabs.com", "White Labs"),
    ("https://wyeastlab.com", "Wyeast"),
    ("https://shop.yakimachief.com", "Yakima Chief"),
    ("https://bsgcraftbrewing.com", "BSG Craft"),
    ("https://www.weyermann.de", "Weyermann"),
    ("https://www.johnihaas.com", "John I Haas"),
    ("https://www.cargill.com/beverage/brewing", "Cargill Brewing"),
    ("https://www.goekos.com", "Ekos"),
    ("https://www.precisionfermentation.com", "Precision Fermentation"),
    ("https://thebeer30.com", "Beer30"),
    ("https://vicinitybrew.com", "VicinityBrew"),
    ("https://www.probrewer.com", "ProBrewer"),
    ("https://www.espn.com", "ESPN"),
    ("https://www.netflix.com", "Netflix"),
    ("https://www.spotify.com", "Spotify"),
    ("https://www.facebook.com", "Facebook"),
    ("https://www.reddit.com/r/nba", "r/NBA"),
    ("https://www.draftkings.com", "DraftKings"),
    ("https://twitter.com", "Twitter")
]

children = []
bid = 5
for i, (url, name) in enumerate(urls):
    children.append({
        "date_added": str(chrome_base - (len(urls)-i)*1000000),
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": url
    })
    bid += 1

bookmarks = {
    "checksum": "0",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(chrome_base), "date_modified": str(chrome_base), "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(chrome_base), "date_modified": str(chrome_base), "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(chrome_base), "date_modified": str(chrome_base), "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

profile_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_dir, exist_ok=True)
with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)

# Clear legacy keywords from Web Data if existing
db_path = os.path.join(profile_dir, "Web Data")
if os.path.exists(db_path):
    try:
        conn = sqlite3.connect(db_path)
        conn.execute("DELETE FROM keywords")
        conn.commit()
        conn.close()
    except Exception:
        pass
EOF

chown -R ga:ga /home/ga/.config/google-chrome

# Start Chrome in the background 
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check about:blank > /dev/null 2>&1 &"
sleep 5

# Focus and maximize window
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Capture initial state 
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="