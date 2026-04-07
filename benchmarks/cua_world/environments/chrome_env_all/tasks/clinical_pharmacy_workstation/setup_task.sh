#!/usr/bin/env bash
set -euo pipefail

echo "=== Clinical Pharmacy Workstation Task Setup ==="

# Record start time
date +%s > /tmp/task_start_time.txt

# Stop Chrome if running to safely modify profile
echo "Stopping Chrome..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Set up required directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/Rx_Transfers"
chown -R ga:ga "/home/ga/Documents/Rx_Transfers"

# Create the SOP Document
cat > "/home/ga/Desktop/pharmacy_browser_sop.txt" << 'EOF'
PHARMACY WORKSTATION CONFIGURATION SOP
======================================
1. BOOKMARK ORGANIZATION
   Create the following folders on the Bookmark Bar and sort existing bookmarks:
   - "Drug Information" (DailyMed, Lexicomp, Epocrates, Micromedex, Medscape, etc.)
   - "Shortages & Recalls" (FDA Shortages, ASHP, CDC Alerts, ISMP, etc.)
   - "Regulatory & Guidelines" (Orange Book, DEA Diversion, Guidelines, PubMed, State Board)
   - "Unauthorized_Personal" (Quarantine all non-clinical/shopping/social media links here)
   * No bookmarks should remain loose on the main bar.

2. SEARCH ENGINE SHORTCUTS
   Create custom site searches for rapid lookups:
   - Keyword: ndc (URL: https://dailymed.nlm.nih.gov/dailymed/search.cfm?labeltype=all&query=%s)
   - Keyword: fda (URL: https://www.accessdata.fda.gov/scripts/cder/daf/index.cfm?event=BasicSearch.process&searchterm=%s)

3. HOMEPAGE
   - Set Homepage to: https://dailymed.nlm.nih.gov

4. PRIVACY & HIPAA COMPLIANCE
   - Disable saving passwords
   - Disable address autofill
   - Disable payment method autofill
   - Block third-party cookies

5. DOWNLOADS
   - Set Default Download Location to: /home/ga/Documents/Rx_Transfers
   - Enable "Ask where to save each file before downloading"
EOF
chown ga:ga "/home/ga/Desktop/pharmacy_browser_sop.txt"

# Create Initial Bookmarks (32 Flat Bookmarks)
echo "Generating chaotic bookmarks..."
python3 << 'PYEOF'
import json
import time

base_time = str((int(time.time()) + 11644473600) * 1000000)

bookmarks_list = [
    # Drug Info (12)
    ("DailyMed", "https://dailymed.nlm.nih.gov/"),
    ("Epocrates", "https://www.epocrates.com/"),
    ("Lexicomp", "https://online.lexi.com/"),
    ("Micromedex", "https://www.micromedexsolutions.com/"),
    ("Drugs.com", "https://www.drugs.com/"),
    ("Medscape", "https://reference.medscape.com/"),
    ("PDR.net", "https://www.pdr.net/"),
    ("RxList", "https://www.rxlist.com/"),
    ("Mayo Clinic Drugs", "https://www.mayoclinic.org/drugs-supplements"),
    ("WebMD Rx", "https://www.webmd.com/drugs/"),
    ("MedlinePlus", "https://medlineplus.gov/druginformation.html"),
    ("Merck Manual", "https://www.merckmanuals.com/professional"),
    # Shortages & Recalls (5)
    ("FDA Drug Shortages", "https://www.accessdata.fda.gov/scripts/drugshortages/"),
    ("ASHP Shortages", "https://www.ashp.org/drug-shortages"),
    ("FDA Recalls", "https://www.fda.gov/safety/recalls-market-withdrawals-safety-alerts"),
    ("CDC Health Alerts", "https://emergency.cdc.gov/han/"),
    ("ISMP Safety", "https://www.ismp.org/"),
    # Regulatory & Guidelines (5)
    ("FDA Orange Book", "https://www.accessdata.fda.gov/scripts/cder/ob/"),
    ("DEA Diversion Control", "https://www.deadiversion.usdoj.gov/"),
    ("CDC Clinical Guidelines", "https://www.cdc.gov/infectioncontrol/guidelines/"),
    ("NIH PubMed", "https://pubmed.ncbi.nlm.nih.gov/"),
    ("State Board of Pharmacy", "https://nabp.pharmacy/"),
    # Personal/Unauthorized (10)
    ("Amazon", "https://www.amazon.com/"),
    ("eBay", "https://www.ebay.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Spotify", "https://open.spotify.com/"),
    ("ESPN", "https://www.espn.com/"),
    ("Pinterest", "https://www.pinterest.com/"),
    ("Twitter", "https://x.com/"),
    ("Weather", "https://weather.com/")
]

children = []
for i, (name, url) in enumerate(bookmarks_list):
    children.append({
        "date_added": base_time,
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_dict = {
    "checksum": "00000000000000000000000000000000",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": base_time,
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": base_time,
            "date_modified": "0",
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": base_time,
            "date_modified": "0",
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks_dict, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome/

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /tmp/chrome_launch.log 2>&1 &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take Initial Screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="