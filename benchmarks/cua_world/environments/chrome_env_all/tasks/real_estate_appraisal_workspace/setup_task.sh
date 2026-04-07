#!/bin/bash
set -euo pipefail

echo "=== Setting up Real Estate Appraisal Workspace Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Chrome is fully stopped
pkill -9 -f chrome 2>/dev/null || true
pkill -9 -f chromium 2>/dev/null || true
sleep 2

# Create the required directories
mkdir -p /home/ga/Documents/Property_Appraisals
chown -R ga:ga /home/ga/Documents

# Prepare Chrome profile directory
CHROME_DIR="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_DIR"

# Briefly start headless Chrome to initialize sqlite databases (History, Cookies, Web Data)
echo "Initializing Chrome databases..."
su - ga -c "google-chrome-stable --headless --disable-gpu --no-sandbox about:blank >/dev/null 2>&1 &"
sleep 4
pkill -9 -f chrome 2>/dev/null || true
sleep 1

# Inject Bookmarks, History, and Cookies using Python for robustness
echo "Injecting task data into Chrome profile..."
cat > /tmp/inject_chrome_data.py << 'PYEOF'
import json, uuid, time, sqlite3, os

CHROME_DIR = "/home/ga/.config/google-chrome/Default"

prof_sites = [
    ("LA County Assessor", "https://assessor.lacounty.gov/"),
    ("San Diego Treasurer", "https://www.sdttc.com/"),
    ("Santa Clara Assessor", "https://www.sccassessor.org/"),
    ("Orange County Gov", "https://www.ocgov.com/"),
    ("San Mateo Assessor", "https://www.smcacre.org/"),
    ("Zillow", "https://www.zillow.com/"),
    ("Realtor", "https://www.realtor.com/"),
    ("Redfin", "https://www.redfin.com/"),
    ("LoopNet", "https://www.loopnet.com/"),
    ("Crexi", "https://www.crexi.com/"),
    ("National Map", "https://apps.nationalmap.gov/viewer/"),
    ("FEMA Flood Maps", "https://msc.fema.gov/portal/home"),
    ("Google Earth", "https://earth.google.com/web/"),
    ("Historic Aerials", "https://www.historicaerials.com/"),
    ("ArcGIS Living Atlas", "https://livingatlas.arcgis.com/"),
    ("First American Title", "https://www.firstam.com/"),
    ("Fidelity National Title", "https://www.fidelity.com/"),
    ("Stewart Title", "https://www.stewart.com/"),
    ("Old Republic Title", "https://www.oldrepublictitle.com/"),
    ("NETR Online", "https://netronline.com/")
]

pers_sites = [
    ("Amazon", "https://www.amazon.com/"),
    ("Wayfair", "https://www.wayfair.com/"),
    ("Overstock", "https://www.overstock.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Hulu", "https://www.hulu.com/"),
    ("Spotify", "https://open.spotify.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Twitter", "https://twitter.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("Macy's", "https://www.macys.com/"),
    ("Nordstrom", "https://www.nordstrom.com/"),
    ("Etsy", "https://www.etsy.com/"),
    ("Target", "https://www.target.com/"),
    ("Walmart", "https://www.walmart.com/"),
    ("BestBuy", "https://www.bestbuy.com/")
]

all_sites = prof_sites + pers_sites
now_webkit = int(time.time() * 1000000) + 11644473600000000

# 1. Bookmarks
children = []
for i, (name, url) in enumerate(all_sites):
    children.append({
        "date_added": str(now_webkit - (i * 1000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "00000000000000000000000000000000",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(now_webkit), "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(now_webkit), "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(now_webkit), "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(CHROME_DIR, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)

# 2. History
hist_path = os.path.join(CHROME_DIR, "History")
if os.path.exists(hist_path):
    try:
        conn = sqlite3.connect(hist_path)
        c = conn.cursor()
        for name, url in all_sites:
            c.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, ?, ?, ?, ?)", 
                      (url, name, 5, 1, now_webkit - 5000000, 0))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Failed to inject History: {e}")

# 3. Cookies (Dynamic insertion to handle schema variations)
cook_path = os.path.join(CHROME_DIR, "Cookies")
if os.path.exists(cook_path):
    try:
        conn = sqlite3.connect(cook_path)
        c = conn.cursor()
        c.execute("PRAGMA table_info(cookies)")
        cols = [row[1] for row in c.fetchall()]
        
        for name, url in all_sites:
            domain = "." + url.split("://")[1].split("/")[0].replace("www.", "")
            vals = []
            for col in cols:
                if col == 'host_key': vals.append(domain)
                elif col == 'name': vals.append("session_token")
                elif col == 'path': vals.append("/")
                elif col in ('creation_utc', 'expires_utc', 'last_access_utc', 'last_update_utc'): vals.append(now_webkit)
                elif col == 'value': vals.append("test_cookie_value")
                elif col == 'encrypted_value': vals.append(b"")
                else: vals.append(0)
            
            placeholders = ",".join(["?"] * len(cols))
            c.execute(f"INSERT INTO cookies ({','.join(cols)}) VALUES ({placeholders})", tuple(vals))
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Failed to inject Cookies: {e}")
PYEOF

python3 /tmp/inject_chrome_data.py
chown -R ga:ga "$CHROME_DIR"

# Write the standards document
cat > /home/ga/Desktop/appraisal_workspace_config.txt << 'EOF'
REAL ESTATE APPRAISAL WORKSPACE STANDARD:
1. Delete all personal/shopping bookmarks. No loose bookmarks on the bar.
2. Group real estate bookmarks into 4 folders: County Assessors, MLS & Listings, Zoning & GIS, Title & Deeds.
3. Remove ALL History and Cookies for the personal/shopping domains. Keep real estate history intact.
4. Add search engines: 'zil' -> https://www.zillow.com/homes/%s_rb/ AND 'red' -> https://www.redfin.com/city/%s
5. Set download dir to: /home/ga/Documents/Property_Appraisals
6. Always ask where to save files before downloading.
7. Set PDFs to download automatically instead of opening in the browser.
EOF
chown ga:ga /home/ga/Desktop/appraisal_workspace_config.txt

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-default-browser-check --no-first-run > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Google Chrome"; then
        DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="