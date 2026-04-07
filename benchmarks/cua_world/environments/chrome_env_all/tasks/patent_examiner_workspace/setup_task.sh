#!/usr/bin/env bash
set -euo pipefail

echo "=== Patent Examiner Workspace Setup ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop Chrome completely to safely inject data
echo "Stopping Chrome..."
pkill -9 -f "chrome" 2>/dev/null || true
sleep 2

# Create Chrome profile directory
CHROME_DIR="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_DIR"

# Write the instruction manual to the Desktop
cat > /home/ga/Desktop/examiner_it_standard.txt << 'EOF'
EXAMINER IT WORKSPACE STANDARD v4.2
===================================
All examiner workstations must adhere to the following Chrome configurations to ensure IP confidentiality and efficiency.

1. BOOKMARK ORGANIZATION
Organize all existing bookmarks into exactly four folders on the Bookmark Bar:
- "Patent Databases" (Google Patents, Espacenet, WIPO, USPTO PatFT/AppFT, Lens, J-PlatPat)
- "Non-Patent Literature" (IEEE, PubMed, ScienceDirect, Nature, Scholar, ACM, arXiv, Wiley)
- "Internal Systems" (USPTO Intranet, WebTA, E-Official Action, PE2E, IT Support)
- "Personal" (Any news, shopping, social media, or entertainment sites)
No bookmarks should remain loose on the main bookmark bar.

2. CONFIDENTIALITY (CRITICAL)
Unreleased patent queries must NEVER be sent to external search prediction services.
- Go to Settings > Sync and Google services -> Disable "Improve search suggestions". 
  (Alternatively: Settings > You and Google > Sync and Google services > "Autocomplete searches and URLs" = OFF)

3. PDF WORKFLOW
Examiners use specialized desktop PDF annotators. Chrome's built-in viewer must be bypassed.
- Go to Settings > Privacy and security > Site Settings > Additional content settings > PDF documents.
- Select "Download PDFs" (Do not open in Chrome).

4. POP-UP EXCEPTIONS
Legacy internal systems require pop-ups.
- Keep the global pop-up blocker ON, but add `[*.]uspto.gov` to the "Allowed to send pop-ups and use redirects" list.

5. CUSTOM SEARCH ENGINES
Add two custom site searches (Settings > Search engine > Manage search engines and site search):
- Keyword: gp
  URL: https://patents.google.com/search?q=%s
- Keyword: wipo
  URL: https://patentscope.wipo.int/search/en/result.jsf?q=%s

6. HISTORY SANITIZATION
This is a repurposed workstation. Delete ALL history entries for personal sites (news, shopping, social media).
Do NOT delete the history of patent databases or NPL searches, as these are needed for continuity.

7. LIVE WORKSPACE
Before starting your examination shift, ensure exactly three tabs are open:
- Google Patents
- IEEE Xplore
- USPTO Intranet
EOF

# Use Python to generate Bookmarks JSON and SQLite History DB
python3 << 'PYEOF'
import json
import sqlite3
import time
import os
import uuid

CHROME_DIR = "/home/ga/.config/google-chrome/Default"
os.makedirs(CHROME_DIR, exist_ok=True)

# 1. GENERATE BOOKMARKS
bookmarks = [
    ("Google Patents", "https://patents.google.com/"),
    ("WIPO PATENTSCOPE", "https://patentscope.wipo.int/"),
    ("Espacenet", "https://worldwide.espacenet.com/"),
    ("Lens.org", "https://www.lens.org/"),
    ("J-PlatPat", "https://www.j-platpat.inpit.go.jp/"),
    ("USPTO PatFT", "https://patft.uspto.gov/"),
    ("USPTO AppFT", "https://appft.uspto.gov/"),
    ("IEEE Xplore", "https://ieeexplore.ieee.org/"),
    ("PubMed", "https://pubmed.ncbi.nlm.nih.gov/"),
    ("ScienceDirect", "https://www.sciencedirect.com/"),
    ("Nature", "https://www.nature.com/"),
    ("Google Scholar", "https://scholar.google.com/"),
    ("ACM Digital Library", "https://dl.acm.org/"),
    ("arXiv", "https://arxiv.org/"),
    ("Wiley Online", "https://onlinelibrary.wiley.com/"),
    ("USPTO Intranet", "https://intranet.uspto.gov/"),
    ("WebTA", "https://webta.uspto.gov/"),
    ("E-Official Action", "https://e-oa.uspto.gov/"),
    ("PE2E", "https://pe2e.uspto.gov/"),
    ("IT Support", "https://itsupport.uspto.gov/"),
    ("CNN News", "https://www.cnn.com/"),
    ("BBC Homepage", "https://www.bbc.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Amazon", "https://www.amazon.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("ESPN Sports", "https://www.espn.com/"),
    ("Twitter", "https://twitter.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Weather", "https://weather.com/"),
    ("Zillow", "https://www.zillow.com/"),
    ("Yelp", "https://www.yelp.com/"),
    ("TripAdvisor", "https://www.tripadvisor.com/"),
    ("Spotify", "https://open.spotify.com/")
]

children = []
chrome_time = (int(time.time()) + 11644473600) * 1000000

for i, (name, url) in enumerate(bookmarks):
    children.append({
        "date_added": str(chrome_time - i * 10000000),
        "guid": str(uuid.uuid4()),
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bm_data = {
    "checksum": "000",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_time),
            "date_modified": str(chrome_time),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open(os.path.join(CHROME_DIR, "Bookmarks"), "w") as f:
    json.dump(bm_data, f, indent=3)

# 2. GENERATE HISTORY DB
db_path = os.path.join(CHROME_DIR, "History")
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE urls (id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)''')

history_entries = [
    ("https://patents.google.com/?q=semiconductor", "Google Patents - semiconductor"),
    ("https://ieeexplore.ieee.org/document/12345", "IEEE Xplore - Novel Transistors"),
    ("https://www.amazon.com/dp/B08F7PTF54", "Amazon.com: Coffee Maker"),
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "YouTube"),
    ("https://patentscope.wipo.int/search/en/result.jsf", "WIPO PATENTSCOPE"),
    ("https://www.cnn.com/2026/03/10/world/news", "CNN Breaking News"),
    ("https://intranet.uspto.gov/hr/benefits", "USPTO HR Benefits"),
    ("https://twitter.com/search?q=tech", "Twitter Search"),
    ("https://www.reddit.com/r/technology", "r/technology - Reddit"),
    ("https://pubmed.ncbi.nlm.nih.gov/234567/", "PubMed Article")
]

for i, (url, title) in enumerate(history_entries):
    t = chrome_time - (i * 3600000000)
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, 1, ?)", (url, title, t))

conn.commit()
conn.close()
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/.config/google-chrome
chown ga:ga /home/ga/Desktop/examiner_it_standard.txt

# Start Chrome with CDP enabled
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --remote-debugging-port=9222 --no-first-run --no-default-browser-check chrome://newtab &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="