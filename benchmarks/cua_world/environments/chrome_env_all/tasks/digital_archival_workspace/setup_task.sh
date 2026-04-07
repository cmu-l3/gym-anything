#!/bin/bash
set -euo pipefail

echo "=== Setting up Digital Archival Workspace Task ==="

# 1. Record start timestamp
date +%s > /tmp/task_start_time.txt

# 2. Stop Chrome if running to safely modify profile
echo "Stopping Chrome..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 3. Create required directories
mkdir -p /home/ga/Documents/Web_Archives
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# 4. Generate Bookmarks file via Python to ensure valid JSON
echo "Generating flat bookmarks (mixed archival + personal)..."
python3 - << 'PYEOF'
import json
import time

base_time = str((int(time.time()) + 11644473600) * 1000000)

bookmarks = [
    {"name": "Internet Archive", "url": "https://archive.org", "type": "url"},
    {"name": "Netflix", "url": "https://www.netflix.com", "type": "url"},
    {"name": "Perma.cc", "url": "https://perma.cc", "type": "url"},
    {"name": "Reddit", "url": "https://www.reddit.com", "type": "url"},
    {"name": "Conifer", "url": "https://conifer.rhizome.org", "type": "url"},
    {"name": "BuzzFeed", "url": "https://www.buzzfeed.com", "type": "url"},
    {"name": "Archive-It", "url": "https://archive-it.org", "type": "url"},
    {"name": "Dublin Core", "url": "https://dublincore.org", "type": "url"},
    {"name": "Twitter", "url": "https://twitter.com", "type": "url"},
    {"name": "PREMIS", "url": "https://www.loc.gov/standards/premis/", "type": "url"},
    {"name": "METS", "url": "https://www.loc.gov/standards/mets/", "type": "url"},
    {"name": "DSpace", "url": "https://dspace.lyrasis.org", "type": "url"},
    {"name": "Fedora Commons", "url": "https://duraspace.org/fedora/", "type": "url"},
    {"name": "EPrints", "url": "https://www.eprints.org", "type": "url"},
    {"name": "Heritrix", "url": "https://github.com/internetarchive/heritrix3", "type": "url"},
    {"name": "Webrecorder", "url": "https://webrecorder.net", "type": "url"}
]

for i, b in enumerate(bookmarks):
    b["id"] = str(i + 5)
    b["date_added"] = base_time

bookmark_data = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": bookmarks,
            "date_added": base_time,
            "date_modified": "0",
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
    json.dump(bookmark_data, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome
chown -R ga:ga /home/ga/Documents/Web_Archives

# 5. Create Specification File
cat > /home/ga/Desktop/archival_browser_spec.txt << 'EOF'
DIGITAL ARCHIVAL WORKSPACE SPECIFICATION v1.2

1. DATA CLEANUP:
   Delete all personal sites from the bookmarks (Netflix, Reddit, BuzzFeed, Twitter/X).
   
2. BOOKMARK ORGANIZATION:
   Organize the remaining 12 archival bookmarks into 4 folders on the Bookmark Bar:
   - "Web Archives" (Internet Archive, Perma.cc, Conifer, Archive-It)
   - "Metadata Standards" (Dublin Core, PREMIS, METS)
   - "Repositories" (DSpace, Fedora Commons, EPrints)
   - "Crawl Tools" (Heritrix, Webrecorder)

3. BROWSER CAPABILITIES (chrome://flags):
   - Enable "Save Page as MHTML" (critical for single-file web capturing)
   - Enable "Enable Reader Mode" (for clean text extraction)

4. CUSTOM SEARCH ENGINE:
   - Name: Wayback
   - Shortcut: ia
   - URL: https://web.archive.org/web/*/%s

5. DOWNLOAD SETTINGS:
   - Set the default download location to: /home/ga/Documents/Web_Archives
   - Turn ON "Ask where to save each file before downloading"

6. PRIVACY & SECURITY:
   - Turn OFF "Preload pages for faster browsing and searching" to prevent 
     Chrome from issuing false HTTP GET requests that pollute target server logs.
EOF
chown ga:ga /home/ga/Desktop/archival_browser_spec.txt

# 6. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check &"
sleep 5

# 7. Maximize Window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# 8. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="