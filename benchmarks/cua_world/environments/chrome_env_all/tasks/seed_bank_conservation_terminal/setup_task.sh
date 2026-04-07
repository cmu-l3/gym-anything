#!/bin/bash
set -euo pipefail

echo "=== Setting up Seed Bank Conservation Terminal task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

export DISPLAY=${DISPLAY:-:1}

# 1. Prepare target directory
TARGET_DIR="/home/ga/Documents/Field_Season_2026"
mkdir -p "$TARGET_DIR"
chown -R ga:ga "$TARGET_DIR"

# 2. Set up local Intranet server with PDFs
SERVER_DIR="/opt/permits_server/permits"
mkdir -p "$SERVER_DIR"

# Minimal valid PDF base64
PDF_B64="JVBERi0xLjEKJcKlwrHDqwoxIDAgb2JqCjw8IC9UeXBlIC9DYXRhbG9nIC9QYWdlcyAyIDAgUiA+PgplbmRvYmoKMiAwIG9iago8PCAvVHlwZSAvUGFnZXMgL0tpZHMgWzMgMCBSXSAvQ291bnQgMSA+PgplbmRvYmoKMyAwIG9iago8PCAvVHlwZSAvUGFnZSAvUGFyZW50IDIgMCBSIC9SZXNvdXJjZXMgNCAwIFIgL01lZGlhQm94IFswIDAgNjEyIDc5Ml0gL0NvbnRlbnRzIDUgMCBSID4+CmVuZG9iago0IDAgb2JqCjw8IC9Gb250IDw8IC9GMSA2IDAgUiA+PiA+PgplbmRvYmoKNSAwIG9iago8PCAvTGVuZ3RoIDQ0ID4+CnN0cmVhbQpCVEQKL0YxIDI0IFRmCjEwMCA3MDAgVGQKKE1pbmltYWwgUERGIFRlc3QpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNiAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EgPj4KZW5kb2JqCnhyZWYKMCA3CjAwMDAwMDAwMDAgNjUzMzUgZiAKMDAwMDAwMDAxNSAwMDAwMCBuIAowMDAwMDAwMDY4IDAwMDAwIG4gCjAwMDAwMDAxMjUgMDAwMDAgbiAKMDAwMDAwMDIyMiAwMDAwMCBuIAowMDAwMDAwMjczIDAwMDAwIG4gCjAwMDAwMDAzNjggMDAwMDAgbiAKdHJhaWxlcgo8PCAvU2l6ZSA3IC9Sb290IDEgMCBSID4+CnN0YXJ0eHJlZgo0NTYKJSVFT0YK"

echo "$PDF_B64" | base64 -d > "$SERVER_DIR/USDA_PPQ_587.pdf"
echo "$PDF_B64" | base64 -d > "$SERVER_DIR/CITES_Export_App.pdf"
echo "$PDF_B64" | base64 -d > "$SERVER_DIR/Field_Collection_Manifest.pdf"

# Create a simple index.html
cat > "$SERVER_DIR/index.html" << 'EOF'
<html><body>
<h1>Internal Field Permits Server</h1>
<ul>
<li><a href="USDA_PPQ_587.pdf">USDA_PPQ_587.pdf</a></li>
<li><a href="CITES_Export_App.pdf">CITES_Export_App.pdf</a></li>
<li><a href="Field_Collection_Manifest.pdf">Field_Collection_Manifest.pdf</a></li>
</ul>
</body></html>
EOF

chown -R ga:ga /opt/permits_server

# Start python HTTP server
pkill -f "python3 -m http.server 8080" || true
su - ga -c "cd /opt/permits_server && nohup python3 -m http.server 8080 > /dev/null 2>&1 &"

# 3. Stop Chrome to safely setup profile
pkill -f "chrome" || true
pkill -f "google-chrome" || true
sleep 2

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome

# 4. Generate Bookmarks JSON dynamically
echo "Generating Chrome bookmarks..."
python3 << 'PYEOF'
import json

personal_domains = [
    ("reddit.com", "Reddit"), ("youtube.com", "YouTube"), ("netflix.com", "Netflix"), 
    ("facebook.com", "Facebook"), ("spotify.com", "Spotify"), ("steampowered.com", "Steam"), 
    ("twitter.com", "Twitter"), ("instagram.com", "Instagram"), ("amazon.com", "Amazon"), 
    ("ebay.com", "eBay"), ("espn.com", "ESPN"), ("weather.com", "Weather"), 
    ("craigslist.org", "Craigslist"), ("pinterest.com", "Pinterest"), ("tumblr.com", "Tumblr")
]

botany_domains = [
    ("ipni.org", "IPNI"), ("worldfloraonline.org", "WFO"), ("tropicos.org", "Tropicos"), 
    ("gbif.org", "GBIF"), ("plants.usda.gov", "USDA Plants"), ("itis.gov", "ITIS"), 
    ("catalogueoflife.org", "CoL"), ("biodiversitylibrary.org", "BHL"), 
    ("data.kew.org/sid", "Kew SID"), ("bgci.org", "BGCI"), ("saveseeds.org", "Save Seeds"), 
    ("croptrust.org", "Crop Trust"), ("aphis.usda.gov", "APHIS"), ("fws.gov", "USFWS"), 
    ("cites.org", "CITES"), ("dec.ny.gov", "NY DEC"), ("natureserve.org", "NatureServe"), 
    ("earthexplorer.usgs.gov", "EarthExplorer"), ("weather.gov", "NOAA"), ("explore.garmin.com", "Garmin")
]

# Mix them up
all_bookmarks = personal_domains + botany_domains

children = []
for i, (domain, name) in enumerate(all_bookmarks):
    children.append({
        "date_added": str(13360000000000000 + i * 1000000),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": f"https://{domain}/" if not domain.startswith("http") else domain
    })

bookmarks = {
    "checksum": "00000000000000000000000000000000",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": "13360000000000000",
            "date_modified": "13360000000000000",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Ensure pristine Preferences and History
rm -f "$CHROME_PROFILE/Preferences"
rm -f "$CHROME_PROFILE/History"*
rm -f "$CHROME_PROFILE/Web Data"*

# 5. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="