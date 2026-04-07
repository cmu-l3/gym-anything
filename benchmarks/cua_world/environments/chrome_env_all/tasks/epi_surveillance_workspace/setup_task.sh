#!/bin/bash
set -e

echo "=== Setting up Epidemiological Surveillance Workspace Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Stop Chrome safely
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true

# 2. Setup Directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p /home/ga/Documents/Surveillance_Data
mkdir -p /tmp/epi_server

# 3. Create Local Server with Real Data
echo "Fetching real epidemiological data..."
cd /tmp/epi_server

# Download real JHU COVID-19 dataset to serve as the linelist
curl -sL "https://raw.githubusercontent.com/CSSEGISandData/COVID-19/master/csse_covid_19_data/csse_covid_19_time_series/time_series_covid19_confirmed_global.csv" -o linelist_anonymized.csv || \
    echo -e "Date,Case,Status\n2026-01-01,1,Confirmed" > linelist_anonymized.csv

# Download a real WHO public PDF (or fallback to minimal valid PDF)
curl -sL "https://www.who.int/docs/default-source/coronaviruse/who-rights-roles-respon-hw-covid-19.pdf" -o case_definitions_2026.pdf || \
    echo -e "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj xref\n0 4\n0000000000 65535 f\n0000000009 00000 n\n0000000052 00000 n\n0000000101 00000 n\ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n178\n%%EOF" > case_definitions_2026.pdf

# Start python HTTP server
python3 -m http.server 8080 > /dev/null 2>&1 &
echo $! > /tmp/epi_server_pid

cd /home/ga

# 4. Create SOP Document
cat > /home/ga/Desktop/epi_workspace_sop.txt << 'EOF'
OUTBREAK SURVEILLANCE WORKSPACE STANDARD (v2.1)

1. BOOKMARKS:
   - Delete all personal/entertainment bookmarks.
   - Create exactly 3 folders on the bookmark bar: "Global Health", "Federal & State", and "Genomic & Academic".
   - Categorize the remaining epidemiological bookmarks into their appropriate folders.

2. FOUNDATIONAL DATASETS:
   - Download the foundational datasets from our local secure server: http://localhost:8080
   - Save both files to: ~/Documents/Surveillance_Data/

3. PRIVACY & PHI HARDENING:
   - To prevent Protected Health Information (PHI) leaks, disable the following in Chrome Settings:
     * Password saving
     * Address and more autofill
     * Payment methods autofill

4. PERFORMANCE FLAGS:
   - We use heavy WebGL/GIS dashboards. Go to chrome://flags and ENABLE:
     * #enable-gpu-rasterization
     * #ignore-gpu-blocklist

5. STARTUP:
   - Configure Chrome to open these specific pages on startup:
     * https://promedmail.org
     * https://www.cdc.gov
EOF

# 5. Inject Flat Bookmarks (15 Epi, 5 Personal interleaved)
python3 << 'PYEOF'
import json

domains = [
    ("who.int", "WHO"), ("netflix.com", "Netflix"), ("ecdc.europa.eu", "ECDC"),
    ("promedmail.org", "ProMED"), ("healthmap.org", "HealthMap"), ("booking.com", "Booking"),
    ("gisaid.org", "GISAID"), ("cdc.gov", "CDC"), ("fda.gov", "FDA"),
    ("steampowered.com", "Steam"), ("health.ny.gov", "NY Health"), ("cdph.ca.gov", "CA Public Health"),
    ("dshs.texas.gov", "TX DSHS"), ("reddit.com", "Reddit"), ("nextstrain.org", "Nextstrain"),
    ("pubmed.ncbi.nlm.nih.gov", "PubMed"), ("instagram.com", "Instagram"), ("coronavirus.jhu.edu", "JHU Dashboard"),
    ("nature.com", "Nature Medicine"), ("thelancet.com", "The Lancet")
]

children = []
for i, (domain, name) in enumerate(domains):
    children.append({
        "date_added": "13360000000000000",
        "id": str(i + 1),
        "name": name,
        "type": "url",
        "url": f"https://{domain}" if not domain.startswith("pubmed") else f"https://{domain}/"
    })

bookmarks = {
    "checksum": "0",
    "roots": {
        "bookmark_bar": {"children": children, "date_added": "13360000000000000", "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": "13360000000000000", "date_modified": "0", "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": "13360000000000000", "date_modified": "0", "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome
chown ga:ga /home/ga/Desktop/epi_workspace_sop.txt
chown -R ga:ga /home/ga/Documents/Surveillance_Data

# 6. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check &"
sleep 5

# Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="