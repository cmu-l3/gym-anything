#!/usr/bin/env bash
set -euo pipefail

echo "=== Setting up Comparative Policy Research Browser Task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 1. Stop Chrome to prepare profile
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 2. Prepare Directories
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
mkdir -p "/home/ga/Documents/Research_Data"

# 3. Create the Specification Document
echo "Creating specification document..."
cat > "/home/ga/Desktop/research_workstation_spec.txt" << 'SPEC_EOF'
CENTER FOR COMPARATIVE POLICY STUDIES
Research Workstation Configuration Standard v4.0

Please configure this browser for the new comparative policy researcher. The browser currently has 30 research bookmarks placed loosely on the bookmark bar. 

REQUIREMENT 1: BOOKMARK ORGANIZATION
Organize the existing bookmarks into exactly 5 folders on the Bookmark Bar:
- "International Organizations": un.org, data.un.org, worldbank.org, data.worldbank.org, oecd.org, stats.oecd.org, imf.org, ilo.org
- "European Union": european-union.europa.eu, ec.europa.eu/eurostat, eur-lex.europa.eu, ecb.europa.eu, fra.europa.eu
- "Latin America": cepal.org, ibge.gov.br, inegi.org.mx, indec.gob.ar, iadb.org
- "Research Databases": jstor.org, scholar.google.com, ssrn.com, ideas.repec.org, scopus.com, webofscience.com, pubmed.ncbi.nlm.nih.gov
- "Data & Visualization": ourworldindata.org, public.tableau.com, observablehq.com, gapminder.org, datatopics.worldbank.org

REQUIREMENT 2: MULTILINGUAL SUPPORT
Go to chrome://settings/languages
Add the following languages to the browser:
- Spanish (es)
- French (fr)
- Portuguese - Brazil (pt-BR)
Ensure Spell Check is turned ON for all of these added languages in addition to English.

REQUIREMENT 3: CHROME EXPERIMENTAL FLAGS
Go to chrome://flags and ENABLE the following features to handle large data and long documents:
- "Smooth Scrolling" (#smooth-scrolling)
- "Parallel downloading" (#enable-parallel-downloading)
- "Tab Scrolling" (#tab-scrolling)

REQUIREMENT 4: CUSTOM SEARCH ENGINES
Add these custom search site shortcuts in Chrome settings:
- Keyword: oecd -> URL: https://www.oecd.org/en/search.html?q=%s
- Keyword: scholar -> URL: https://scholar.google.com/scholar?q=%s
- Keyword: wb -> URL: https://datacatalog.worldbank.org/search?q=%s

REQUIREMENT 5: BROWSER PREFERENCES
- Homepage: Show home button and set to https://data.un.org
- On Startup: Open specific pages: https://data.un.org, https://stats.oecd.org, and https://scholar.google.com
- Privacy: Block third-party cookies AND enable "Send a Do Not Track request"
- Downloads: Set location to /home/ga/Documents/Research_Data AND turn on "Ask where to save each file before downloading"
- Passwords: Turn OFF "Offer to save passwords"
SPEC_EOF

# 4. Create Initial Flat Bookmarks JSON via Python
echo "Generating bookmarks JSON..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_list = [
    ("United Nations", "https://www.un.org"),
    ("UN Data", "https://data.un.org"),
    ("World Bank", "https://www.worldbank.org"),
    ("World Bank Open Data", "https://data.worldbank.org"),
    ("OECD", "https://www.oecd.org"),
    ("OECD Statistics", "https://stats.oecd.org"),
    ("IMF", "https://www.imf.org"),
    ("ILO", "https://www.ilo.org"),
    ("European Union", "https://european-union.europa.eu"),
    ("Eurostat", "https://ec.europa.eu/eurostat"),
    ("EUR-Lex", "https://eur-lex.europa.eu"),
    ("European Central Bank", "https://www.ecb.europa.eu"),
    ("EU Fundamental Rights Agency", "https://fra.europa.eu"),
    ("ECLAC (CEPAL)", "https://www.cepal.org"),
    ("IBGE Brazil", "https://www.ibge.gov.br"),
    ("INEGI Mexico", "https://www.inegi.org.mx"),
    ("INDEC Argentina", "https://www.indec.gob.ar"),
    ("Inter-American Development Bank", "https://www.iadb.org"),
    ("JSTOR", "https://www.jstor.org"),
    ("Google Scholar", "https://scholar.google.com"),
    ("SSRN", "https://www.ssrn.com"),
    ("RePEc IDEAS", "https://ideas.repec.org"),
    ("Scopus", "https://www.scopus.com"),
    ("Web of Science", "https://www.webofscience.com"),
    ("PubMed", "https://pubmed.ncbi.nlm.nih.gov"),
    ("Our World in Data", "https://ourworldindata.org"),
    ("Tableau Public", "https://public.tableau.com"),
    ("Observable", "https://observablehq.com"),
    ("Gapminder", "https://gapminder.org"),
    ("World Development Indicators", "https://datatopics.worldbank.org")
]

children = []
for i, (name, url) in enumerate(bookmarks_list):
    children.append({
        "date_added": str(chrome_base - (30 - i) * 600000000),
        "guid": str(uuid.uuid4()),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
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
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/Desktop/research_workstation_spec.txt
chown -R ga:ga /home/ga/.config/google-chrome
chown -R ga:ga /home/ga/Documents/Research_Data

# 5. Launch Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check --disable-session-crashed-bubble > /dev/null 2>&1 &"

# Wait for window
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        break
    fi
    sleep 1
done

# Maximize Chrome and open spec doc side-by-side or just focus
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="