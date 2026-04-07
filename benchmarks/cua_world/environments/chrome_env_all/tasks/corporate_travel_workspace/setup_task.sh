#!/usr/bin/env bash
set -euo pipefail

echo "=== Corporate Travel Workspace Task Setup ==="
echo "Task: Configure browser per travel IT specification"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Wait for environment to stabilize
sleep 2

# Stop Chrome to safely construct the initial profile state
echo "Stopping Chrome to prepare profile..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# 1. Generate the Specification Document
cat > "/home/ga/Desktop/travel_workspace_spec.txt" << 'SPEC_EOF'
CORPORATE TRAVEL WORKSPACE - BROWSER SPECIFICATION v2.1

1. BOOKMARK ORGANIZATION
All loose travel bookmarks MUST be organized into exactly four folders on the Bookmark Bar:

Folder: Oneworld
- American Airlines, British Airways, Qantas, Cathay Pacific, Japan Airlines, Finnair, Iberia

Folder: SkyTeam
- Delta, Air France, KLM, Korean Air, Aeromexico, Virgin Atlantic, ITA Airways

Folder: Star Alliance
- United, Lufthansa, ANA, Air Canada, Singapore Airlines, TAP Air Portugal, EVA Air, Swiss, Asiana

Folder: Hotels
- Marriott, Hilton, Hyatt, IHG, Radisson, Wyndham, Choice

2. GLOBAL SECURITY POLICY
To comply with InfoSec Policy 404:
- Third-party cookies MUST be blocked globally.
- Pop-ups and redirects MUST be blocked globally.
- Password saving MUST be disabled (do not save client portal credentials).

3. SITE-SPECIFIC EXCEPTIONS (CRITICAL FOR BOOKING)
The following enterprise portals will break if blocked. You must add them to the "Allowed" list for BOTH Cookies and Pop-ups:
- [*.]concursolutions.com
- [*.]amadeus.com

4. CUSTOM SEARCH ENGINE
Add a site search shortcut for rapid flight tracking:
- Search engine name: FlightAware
- Shortcut / Keyword: fa
- URL with %s in place of query: https://www.flightaware.com/live/flight/%s

5. STARTUP BEHAVIOR
- Set Chrome to "Continue where you left off" to preserve active booking sessions.
SPEC_EOF
chown ga:ga "/home/ga/Desktop/travel_workspace_spec.txt"

# 2. Generate Initial Bookmarks (30 loose flat bookmarks) using Python to ensure valid JSON
echo "Generating initial bookmarks payload..."
python3 << 'PYEOF'
import json
import time

chrome_base = (int(time.time()) + 11644473600) * 1000000

sites = [
    ("American Airlines", "https://www.aa.com"),
    ("British Airways", "https://www.britishairways.com"),
    ("Qantas", "https://www.qantas.com"),
    ("Cathay Pacific", "https://www.cathaypacific.com"),
    ("Japan Airlines", "https://www.jal.co.jp"),
    ("Finnair", "https://www.finnair.com"),
    ("Iberia", "https://www.iberia.com"),
    ("Delta", "https://www.delta.com"),
    ("Air France", "https://www.airfrance.com"),
    ("KLM", "https://www.klm.com"),
    ("Korean Air", "https://www.koreanair.com"),
    ("Aeromexico", "https://www.aeromexico.com"),
    ("Virgin Atlantic", "https://www.virginatlantic.com"),
    ("ITA Airways", "https://www.ita-airways.com"),
    ("United", "https://www.united.com"),
    ("Lufthansa", "https://www.lufthansa.com"),
    ("ANA", "https://www.ana.co.jp"),
    ("Air Canada", "https://www.aircanada.com"),
    ("Singapore Airlines", "https://www.singaporeair.com"),
    ("TAP Air Portugal", "https://www.flytap.com"),
    ("EVA Air", "https://www.evaair.com"),
    ("Swiss", "https://www.swiss.com"),
    ("Asiana", "https://www.flyasiana.com"),
    ("Marriott", "https://www.marriott.com"),
    ("Hilton", "https://www.hilton.com"),
    ("Hyatt", "https://www.hyatt.com"),
    ("IHG", "https://www.ihg.com"),
    ("Radisson", "https://www.radissonhotels.com"),
    ("Wyndham", "https://www.wyndhamhotels.com"),
    ("Choice Hotels", "https://www.choicehotels.com")
]

children = []
for i, (name, url) in enumerate(sites):
    children.append({
        "date_added": str(chrome_base - (i * 10000000)),
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

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w', encoding='utf-8') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# 3. Create clean baseline preferences
cat > "$CHROME_PROFILE/Preferences" << 'PREF_EOF'
{
   "profile": {
      "cookie_controls_mode": 0,
      "default_content_setting_values": {
         "popups": 1,
         "cookies": 1
      },
      "password_manager_enabled": true
   },
   "session": {
      "restore_on_startup": 5
   }
}
PREF_EOF
chown ga:ga "$CHROME_PROFILE/Preferences"

# 4. Launch Chrome in the background for the agent
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable > /dev/null 2>&1 &"
sleep 5

# Ensure window is maximized
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="