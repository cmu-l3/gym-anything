#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Customs Broker Workspace Task ==="
echo "Task: Configure browser per Trade Compliance standard"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Stop Chrome to safely modify profile
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chromium" 2>/dev/null || true
sleep 2

# The environment uses google-chrome-cdp for automated Chrome instances
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp" 2>/dev/null || true

# 1. Create the spec file
echo "Creating Trade Compliance Browser Configuration Guide..."
cat > "/home/ga/Desktop/trade_compliance_browser_guide.txt" << 'SPEC_EOF'
MERIDIAN LOGISTICS INC.
Trade Compliance Browser Configuration Guide v4.1

1. BOOKMARK ORGANIZATION
Organize all bookmarks on the bookmark bar into exactly five folders:
- "Government Portals" (CBP ACE, USITC, FDA, USDA APHIS, AESDirect, TTB, FMC, CROSS)
- "Carriers & Logistics" (Maersk, MSC, CMA CGM, FedEx, UPS, Flexport)
- "Trade Databases" (CustomsInfo, WCO, WTO, UN Comtrade, Export.gov, Trade.gov, FTZ)
- "Industry Resources" (NCBFAA, AAEI, JOC, American Shipper, FreightWaves)
- "Non-Work" (Move all personal/entertainment bookmarks here. No personal bookmarks should be loose on the bar.)

2. SEARCH ENGINE SHORTCUTS (Custom Search Engines)
Add the following site searches to save time on classifications:
- Keyword: hts     -> URL: https://hts.usitc.gov/?query=%s
- Keyword: ruling  -> URL: https://rulings.cbp.gov/search?term=%s
- Keyword: vessel  -> URL: https://www.marinetraffic.com/en/ais/index/search/all?keyword=%s

3. HOMEPAGE & STARTUP
- Homepage: https://ace.cbp.dhs.gov
- Startup Pages: Open specific pages on startup (ace.cbp.dhs.gov AND hts.usitc.gov)

4. APPEARANCE
- Default font size: 18 (Required to clearly read dense Harmonized Tariff Schedule tables)

5. PRIVACY & SECURITY
- Block third-party cookies
- Send "Do Not Track" request
- Safe Browsing: Enhanced Protection mode

6. DOWNLOADS & CREDENTIALS
- Download Location: /home/ga/Documents/Customs_Filings
- Always ask where to save each file before downloading
- Disable saving passwords
- Disable address and payment method autofill
SPEC_EOF
chown ga:ga "/home/ga/Desktop/trade_compliance_browser_guide.txt"

# 2. Create the target download directory
mkdir -p "/home/ga/Documents/Customs_Filings"
chown ga:ga "/home/ga/Documents/Customs_Filings"

# 3. Use Python to generate flat, unorganized bookmarks JSON reliably
python3 << 'PYEOF'
import json, time, uuid, os

# Base timestamp (WebKit)
chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_list = [
    # Government Portals
    ("CBP ACE Portal", "https://ace.cbp.dhs.gov"), ("USITC HTS Search", "https://hts.usitc.gov"),
    ("CBP CROSS Rulings", "https://rulings.cbp.gov"), ("FDA Import Program", "https://www.fda.gov"),
    ("USDA APHIS", "https://www.aphis.usda.gov"), ("Census AESDirect", "https://aesdirect.gov"),
    ("TTB Permits Online", "https://www.ttbonline.gov"), ("FMC Licensing", "https://www.fmc.gov"),
    # Carriers
    ("Maersk", "https://www.maersk.com"), ("MSC", "https://www.msc.com"),
    ("CMA CGM", "https://www.cma-cgm.com"), ("FedEx Trade", "https://www.fedex.com"),
    ("UPS Trade Management", "https://www.ups.com"), ("Flexport", "https://www.flexport.com"),
    # Trade Databases
    ("Descartes CustomsInfo", "https://www.customsinfo.com"), ("World Customs Organization", "https://www.wcoomd.org"),
    ("WTO Tariff Data", "https://www.wto.org"), ("UN Comtrade", "https://comtrade.un.org"),
    ("Export.gov", "https://www.export.gov"), ("ITA", "https://www.trade.gov"),
    ("FTZ Board", "https://www.trade.gov/ftz"),
    # Industry
    ("NCBFAA", "https://www.ncbfaa.org"), ("AAEI", "https://www.aaei.net"),
    ("Journal of Commerce", "https://www.joc.com"), ("American Shipper", "https://www.americanshipper.com"),
    ("FreightWaves", "https://www.freightwaves.com"),
    # Personal/Non-Work
    ("Reddit", "https://www.reddit.com"), ("YouTube", "https://www.youtube.com"),
    ("ESPN", "https://www.espn.com"), ("Amazon", "https://www.amazon.com"),
    ("Netflix", "https://www.netflix.com"), ("Spotify", "https://www.spotify.com"),
    ("Twitter", "https://x.com"), ("Instagram", "https://www.instagram.com"),
    ("LinkedIn", "https://www.linkedin.com")
]

# Shuffle deterministically for this initial state
import random
random.seed(42)
random.shuffle(bookmarks_list)

children = []
for i, (name, url) in enumerate(bookmarks_list):
    children.append({
        "date_added": str(chrome_base - (i * 10000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_json = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(chrome_base), "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(chrome_base), "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome-cdp/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks_json, f, indent=3)

# Create a non-compliant initial Preferences file
prefs_json = {
    "browser": {"show_home_button": True},
    "homepage": "https://www.google.com",
    "homepage_is_newtabpage": False,
    "webkit": {"webprefs": {"default_font_size": 16}},
    "download": {"default_directory": "/home/ga/Downloads", "prompt_for_download": False},
    "profile": {"cookie_controls_mode": 0, "password_manager_enabled": True},
    "credentials_enable_service": True,
    "autofill": {"profile_enabled": True, "credit_card_enabled": True},
    "safebrowsing": {"enabled": True, "enhanced": False},
    "enable_do_not_track": False
}
with open('/home/ga/.config/google-chrome-cdp/Default/Preferences', 'w') as f:
    json.dump(prefs_json, f, indent=3)
PYEOF

chown -R ga:ga "/home/ga/.config/google-chrome-cdp/Default"

# Record initial count (should be 35)
echo "35" > /tmp/initial_bookmark_count.txt

# Start Chrome via the environment's script
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome\|Chromium"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool mousemove 960 540 click 1 || true

echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="