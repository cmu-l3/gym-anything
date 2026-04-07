#!/bin/bash
set -euo pipefail

echo "=== Setting up SRE Incident Command Setup Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop any running Chrome instances
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Prepare Chrome profile directory
CHROME_DIR="/home/ga/.config/google-chrome"
CHROME_PROFILE="$CHROME_DIR/Default"
mkdir -p "$CHROME_PROFILE"

# Create the standard document on the Desktop
cat > /home/ga/Desktop/noc_display_standard.txt << 'EOF'
NOC DISPLAY BROWSER STANDARD
----------------------------
1. Live Monitoring Tabs:
   Open these 3 tabs and leave them active in the browser:
   - https://app.datadoghq.com/dashboard/system
   - https://pagerduty.com/incidents
   - https://us-east-1.console.aws.amazon.com/ec2

2. Bookmark Organization (on Bookmark Bar):
   - Delete all personal/junk bookmarks.
   - Create folder "Alerting" and put inside: PagerDuty, Opsgenie, Statuspage, VictorOps
   - Create folder "Observability" and put inside: Datadog, Grafana, Splunk, New Relic
   - Create folder "Cloud Infrastructure" and put inside: AWS, GCP, Azure, Cloudflare
   - Create folder "Runbooks" and put inside: Confluence, GitHub, GitLab, Runbooks.io

3. Custom Search Engines (Manage search engines):
   - Shortcut 'pd' -> https://pagerduty.com/search?q=%s
   - Shortcut 'tkt' -> https://jira.internal.noc/browse/%s

4. Notifications (Site Settings):
   - Default behavior: Don't allow sites to send notifications
   - Allowed exceptions (explicitly allow):
     * https://pagerduty.com
     * https://datadoghq.com

5. Appearance & Display:
   - Font Size: Default (Standard) = 22, Fixed-width = 18

6. Performance Flags (chrome://flags):
   - Enable GPU rasterization (search: enable-gpu-rasterization)
   - Enable Smooth Scrolling (search: smooth-scrolling)

7. On Startup:
   - "Open a specific page or set of pages"
   - Add the 3 Live Monitoring Tabs from Step 1.
EOF

# Use Python to generate the initial messy Bookmarks JSON
python3 << 'PYEOF'
import json
import time

base_time = "13360799510000000"

sre_bookmarks = [
    ("PagerDuty", "https://pagerduty.com/"),
    ("Opsgenie", "https://opsgenie.com/"),
    ("Statuspage", "https://statuspage.io/"),
    ("VictorOps", "https://victorops.com/"),
    ("Datadog", "https://datadoghq.com/"),
    ("Grafana", "https://grafana.com/"),
    ("Splunk", "https://splunk.com/"),
    ("New Relic", "https://newrelic.com/"),
    ("AWS Console", "https://aws.amazon.com/"),
    ("GCP Console", "https://cloud.google.com/"),
    ("Azure Portal", "https://azure.microsoft.com/"),
    ("Cloudflare", "https://cloudflare.com/"),
    ("Confluence", "https://confluence.net/"),
    ("GitHub", "https://github.com/"),
    ("GitLab", "https://gitlab.com/"),
    ("Runbooks", "https://runbooks.io/")
]

junk_bookmarks = [
    ("Facebook", "https://facebook.com/"),
    ("Netflix", "https://netflix.com/"),
    ("Twitter", "https://twitter.com/"),
    ("Reddit", "https://reddit.com/"),
    ("Pinterest", "https://pinterest.com/"),
    ("Steam", "https://steampowered.com/"),
    ("Spotify", "https://spotify.com/"),
    ("TikTok", "https://tiktok.com/")
]

# Mix them up
all_bms = []
for i in range(8):
    all_bms.append(sre_bookmarks[i])
    all_bms.append(junk_bookmarks[i])
    all_bms.append(sre_bookmarks[i+8])

children = []
for i, (name, url) in enumerate(all_bms):
    children.append({
        "date_added": str(int(base_time) + i * 10000),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_json = {
    "checksum": "0000000000000000",
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

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks_json, f, indent=3)
PYEOF

chown -R ga:ga /home/ga/.config/google-chrome/
chown ga:ga /home/ga/Desktop/noc_display_standard.txt

# Start Chrome with CDP enabled
echo "Starting Chrome..."
su - ga -c "/home/ga/launch_chrome.sh about:blank &"
sleep 5

# Ensure window is active and maximized
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="