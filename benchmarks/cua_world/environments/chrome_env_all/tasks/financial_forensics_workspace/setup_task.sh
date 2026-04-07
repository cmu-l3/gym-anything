#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Financial Forensics Workspace task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop Chrome if running
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3

# Setup profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# Create OpSec Standard Document
cat > /home/ga/Desktop/Investigation_OpSec_Standard.txt << 'EOF'
OPERATION GOLDEN FLEECE - WORKSTATION OPSEC STANDARD

1. BOOKMARK ORGANIZATION
Create the following folders on the bookmark bar and categorize the relevant OSINT links:
- Sanctions & Watchlists (OFAC, UN, EU, FATF)
- Corporate Registries (OpenCorporates, Companies House, SEC, Delaware, Zefix)
- Intelligence Databases (ICIJ, OCCRP, Investigative Dashboard)
- Asset Tracking (Zillow, ACRIS, MarineTraffic, FlightRadar24)

2. OPSEC SANITIZATION
CRITICAL: You must completely DELETE all personal/entertainment bookmarks (Facebook, Pinterest, Amazon, Netflix, Spotify, Expedia, TripAdvisor). Do not just move them; delete them.

3. RAPID ENTITY SEARCH SHORTCUTS
Add the following custom search engines (Settings > Search engine > Manage search engines and site search):
- OpenCorporates | Shortcut: oc | URL: https://opencorporates.com/companies?q=%s
- ICIJ Offshore Leaks | Shortcut: icij | URL: https://offshoreleaks.icij.org/search?q=%s
- OFAC Sanctions | Shortcut: ofac | URL: https://sanctionssearch.ofac.treas.gov/Details.aspx?id=%s

4. PRIVACY HARDENING
- Block third-party cookies
- Send a "Do Not Track" request with your browsing traffic
- Set Safe Browsing to "Enhanced protection"

5. EVIDENCE HANDLING
- Set Download location to: /home/ga/Documents/Case_GoldenFleece/Evidence
- Turn ON "Ask where to save each file before downloading"

6. STARTUP CONFIGURATION
- On startup, open these specific pages:
  * https://offshoreleaks.icij.org/
  * https://opencorporates.com/
EOF
chown ga:ga /home/ga/Desktop/Investigation_OpSec_Standard.txt

# Create Evidence Directory
mkdir -p /home/ga/Documents/Case_GoldenFleece/Evidence
chown -R ga:ga /home/ga/Documents/Case_GoldenFleece

# Generate Bookmarks
echo "Creating initial bookmarks..."
python3 << 'PYEOF'
import json, time, uuid

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_data = [
    ("OFAC Sanctions", "https://sanctionssearch.ofac.treas.gov/"),
    ("UN Security Council", "https://www.un.org/securitycouncil/sanctions/"),
    ("EU Sanctions Map", "https://www.sanctionsmap.eu/"),
    ("FATF", "https://www.fatf-gafi.org/"),
    ("OpenCorporates", "https://opencorporates.com/"),
    ("UK Companies House", "https://www.gov.uk/government/organisations/companies-house"),
    ("SEC EDGAR", "https://www.sec.gov/edgar/"),
    ("Delaware Div of Corp", "https://corp.delaware.gov/"),
    ("Swiss Zefix", "https://www.zefix.ch/"),
    ("ICIJ Offshore Leaks", "https://offshoreleaks.icij.org/"),
    ("OCCRP Aleph", "https://aleph.occrp.org/"),
    ("Investigative Dashboard", "https://investigativedashboard.org/"),
    ("Zillow", "https://www.zillow.com/"),
    ("NYC ACRIS", "https://a836-acris.nyc.gov/"),
    ("MarineTraffic", "https://www.marinetraffic.com/"),
    ("FlightRadar24", "https://www.flightradar24.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Pinterest", "https://www.pinterest.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Spotify", "https://www.spotify.com/"),
    ("Expedia", "https://www.expedia.com/"),
    ("TripAdvisor", "https://www.tripadvisor.com/")
]

children = []
for i, (name, url) in enumerate(bookmarks_data):
    children.append({
        "date_added": str(chrome_base - (23-i) * 600000000),
        "guid": str(uuid.uuid4()),
        "id": str(5+i),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": str(chrome_base),
            "date_modified": "0",
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": str(chrome_base),
            "date_modified": "0",
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Start Chrome in the background
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh > /tmp/chrome_launch.log 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="