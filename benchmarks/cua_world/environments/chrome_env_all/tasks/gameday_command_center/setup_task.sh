#!/bin/bash
echo "=== Setting up Game Day Command Center Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create standard document
cat > /home/ga/Desktop/gameday_browser_standard.txt << 'EOF'
ANALYTICS DEPARTMENT - GAME DAY BROWSER STANDARD v2.0
=====================================================
All press box analysts must configure their Chrome workspaces exactly as follows before first pitch.

1. BOOKMARK ORGANIZATION
Organize the current bookmarks on your bookmark bar into exactly 6 folders:
- "Advanced Analytics" (FanGraphs, Baseball Savant, Brooks Baseball, Statcast, Tango Tiger, Baseball Prospectus, Baseball Reference)
- "Live Scoring" (MLB Scores, ESPN Scoreboard, CBS Sports, Yahoo MLB, MiLB Scores)
- "Historical Reference" (Retrosheet, Seamheads, SABR, Baseball Almanac)
- "Scouting & Player Dev" (Kinatrax, Rapsodo, Trackman, Driveline, Prospects Live)
- "League Operations" (MiLB Home, Transactions, Standings, Stats)
- "Personal - Off Clock" (YouTube, Reddit, Twitter, Instagram, Twitch, Spotify, Amazon). NO personal bookmarks should be loose on the main bar.

2. LIVE WORKSPACE
Keep exactly these 5 tabs open for the live game dashboard:
- FanGraphs (fangraphs.com)
- Baseball Savant (baseballsavant.mlb.com)
- MLB Scores (mlb.com/scores)
- MiLB Scores (milb.com/scores)
- Baseball Reference (baseball-reference.com)

3. DISPLAY & PERFORMANCE (PRESS BOX OPTIMIZED)
- Font Size: Go to Chrome Settings > Appearance. Change the Font size to "Large" or custom size 20 (we sit far from the screens).
- Chrome Flags: Navigate to chrome://flags
  * Set "Parallel downloading" to Enabled (improves media loading on stadium Wi-Fi)
  * Set "Smooth Scrolling" to Disabled (reduces input lag on live score feeds)

4. BROWSER BEHAVIOR & PRIVACY
- Homepage: Set to https://www.mlb.com/scores
- On Startup: "Continue where you left off"
- Downloads: Set location to /home/ga/Documents/GameDay_Data and turn ON "Ask where to save each file before downloading"
- Privacy: Block third-party cookies
- Autofill: Turn OFF password saving and address/payment autofill (shared device security)

5. CHECKLIST
Create a file at ~/Desktop/pregame_checklist.txt summarizing what you completed. Mentions of "bookmarks", "tabs", "flags", and "privacy" are required.
EOF

chown ga:ga /home/ga/Desktop/gameday_browser_standard.txt

# Create download directory
mkdir -p /home/ga/Documents/GameDay_Data
chown ga:ga /home/ga/Documents/GameDay_Data

# Prepare Chrome profile
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# Stop Chrome if running
pkill -f chrome 2>/dev/null || true
sleep 2

# Create flat bookmarks file using Python
python3 << 'PYEOF'
import json

bookmarks_list = [
    ("https://www.baseball-reference.com", "Baseball Reference"),
    ("https://www.fangraphs.com", "FanGraphs"),
    ("https://baseballsavant.mlb.com", "Baseball Savant"),
    ("https://www.brooksbaseball.net", "Brooks Baseball"),
    ("https://www.mlb.com/glossary/statcast", "Statcast Glossary"),
    ("https://www.tangotiger.com", "Tango Tiger"),
    ("https://www.baseballprospectus.com", "Baseball Prospectus"),
    ("https://www.mlb.com/scores", "MLB Scores"),
    ("https://www.espn.com/mlb/scoreboard", "ESPN MLB Scoreboard"),
    ("https://www.cbssports.com/mlb/scores/", "CBS Sports MLB"),
    ("https://sports.yahoo.com/mlb/scoreboard/", "Yahoo MLB"),
    ("https://www.milb.com/scores", "MiLB Scores"),
    ("https://www.retrosheet.org", "Retrosheet"),
    ("https://www.seamheads.com", "Seamheads"),
    ("https://sabr.org", "SABR"),
    ("https://www.baseball-almanac.com", "Baseball Almanac"),
    ("https://www.kinatrax.com", "Kinatrax"),
    ("https://rapsodo.com", "Rapsodo"),
    ("https://www.trackman.com/baseball", "Trackman Baseball"),
    ("https://www.drivelinebaseball.com", "Driveline Baseball"),
    ("https://www.prospectslive.com", "Prospects Live"),
    ("https://www.milb.com", "MiLB Home"),
    ("https://www.milb.com/transactions", "MiLB Transactions"),
    ("https://www.milb.com/standings", "MiLB Standings"),
    ("https://www.milb.com/stats", "MiLB Stats"),
    ("https://www.youtube.com", "YouTube"),
    ("https://www.reddit.com", "Reddit"),
    ("https://www.twitter.com", "Twitter"),
    ("https://www.instagram.com", "Instagram"),
    ("https://www.twitch.tv", "Twitch"),
    ("https://open.spotify.com", "Spotify"),
    ("https://www.amazon.com", "Amazon")
]

children = []
for i, (url, name) in enumerate(bookmarks_list):
    children.append({
        "date_added": "13370000000000000",
        "id": str(i + 10),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks_json = {
    "checksum": "00000000000000000000000000000000",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": "13370000000000000",
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
        "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks_json, f, indent=3)
PYEOF

chown ga:ga /home/ga/.config/google-chrome/Default/Bookmarks

# Launch Chrome using the environment's CDP launcher
if [ -f /home/ga/launch_chrome.sh ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank &"
else
    su - ga -c "DISPLAY=:1 google-chrome --remote-debugging-port=9222 --remote-allow-origins=* about:blank &"
fi

# Wait for Chrome window
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -iq "chrome"; then
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool search --onlyvisible --class "chrome" windowactivate 2>/dev/null || true

# Take initial screenshot
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="