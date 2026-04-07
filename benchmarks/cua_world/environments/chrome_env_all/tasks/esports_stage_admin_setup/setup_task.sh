#!/bin/bash
set -euo pipefail

echo "=== Setting up E-sports Stage Admin Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Stop Chrome safely
echo "Stopping Chrome..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# 2. Prepare Chrome Profile Directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
CHROME_CDP_PROFILE="/home/ga/.config/google-chrome-cdp/Default"

for PROFILE in "$CHROME_PROFILE" "$CHROME_CDP_PROFILE"; do
    mkdir -p "$PROFILE"
    
    # Generate 25 flat bookmarks via Python
    python3 << PYEOF
import json
import time

domains = [
    "smash.gg", "challonge.com", "liquipedia.net", "battlefy.com", "toornament.com",
    "twitch.tv", "youtube.com", "restream.io", "obs.ninja", "vdo.ninja",
    "faceit.com", "esea.net", "riotgames.com", "easy.ac", "battleye.com",
    "discord.com", "teamspeak.com", "slack.com", "mumble.info", "guilded.gg",
    "twitter.com", "reddit.com", "amazon.com", "netflix.com", "espn.com"
]

names = [
    "Smash.gg", "Challonge", "Liquipedia", "Battlefy", "Toornament",
    "Twitch", "YouTube", "Restream", "OBS Ninja", "VDO Ninja",
    "FACEIT", "ESEA", "Riot Games", "Easy Anti-Cheat", "BattlEye",
    "Discord", "TeamSpeak", "Slack", "Mumble", "Guilded",
    "Twitter", "Reddit", "Amazon", "Netflix", "ESPN"
]

base_time = str((int(time.time()) + 11644473600) * 1000000)
children = []

for i, (domain, name) in enumerate(zip(domains, names)):
    children.append({
        "date_added": base_time,
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": f"https://{domain}/"
    })

bookmarks = {
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
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("$PROFILE/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
done

chown -R ga:ga /home/ga/.config/google-chrome*

# 3. Create the protocol document
cat > /home/ga/Desktop/stage_admin_protocol.txt << 'EOF'
E-SPORTS MAIN STAGE ADMIN TERMINAL - BROWSER PROTOCOL

1. BOOKMARKS
Organize the 25 loose bookmarks on the bookmark bar into exactly 5 folders:
- "Brackets & Scoring" (smash.gg, challonge, liquipedia, battlefy, toornament)
- "Stream Management" (twitch, youtube, restream, obs.ninja, vdo.ninja)
- "Anti-Cheat Portals" (faceit, esea, riotgames, easy.ac, battleye)
- "Team Comms" (discord, teamspeak, slack, mumble, guilded)
- "Personal" (twitter, reddit, amazon, netflix, espn)

2. PERFORMANCE SETTINGS
- Navigate to chrome://settings/performance
- Turn OFF "Memory Saver". (Critical: Background bracket WebSockets must not sleep).

3. MEDIA PERMISSIONS
- Navigate to chrome://settings/content
- Default Sound: Block sites from playing sound (Mute all).
- Explicit Exception: Add an "Allow" exception for "https://discord.com".
- Default Microphone: Block sites from using the mic.
- Explicit Exception: Add an "Allow" exception for "https://discord.com".

4. NETWORKING FLAGS
- Navigate to chrome://flags
- Search for "Experimental QUIC protocol" (#enable-quic) and set it to "Disabled". (Prevents legacy match-server disconnects).

5. SEARCH & STARTUP
- Add a custom search engine: Keyword: "vlr", URL: "https://www.vlr.gg/search/?q=%s"
- Set browser startup to open exactly two pages: "https://discord.com/app" and "https://battlefy.com".
EOF
chown ga:ga /home/ga/Desktop/stage_admin_protocol.txt

# 4. Launch Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh > /dev/null 2>&1 &"
sleep 5

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="