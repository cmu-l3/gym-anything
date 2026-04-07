#!/usr/bin/env bash
set -euo pipefail

echo "=== Wind Farm SCADA Console Task Setup ==="
echo "Task: Configure browser per field operations standard"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for X/VNC to be ready
sleep 2

# ── 1. Stop Chrome safely ───────────────────────────────────────────────────
echo "Stopping Chrome to inject test data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# ── 2. Prepare Chrome profile directory ─────────────────────────────────────
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# ── 3. Create Bookmarks JSON ────────────────────────────────────────────────
echo "Creating Bookmarks file with 24 flat entries (16 legit + 8 junk)..."
python3 << 'PYEOF'
import json, time, uuid

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_data = [
    # Operational - Weather (3)
    ("National Weather Service", "https://www.nws.noaa.gov/"),
    ("Windy High-Res", "https://www.windy.com/"),
    ("NOAA Storm Prediction Center", "https://www.spc.noaa.gov/"),
    
    # Operational - SCADA (4)
    ("SCADA Login", "https://scada.blueridge-wind.local/login"),
    ("SCADA Main Dashboard", "https://scada.blueridge-wind.local/dashboard"),
    ("SCADA Active Alarms", "https://scada.blueridge-wind.local/alarms"),
    ("SCADA Production Reports", "https://scada.blueridge-wind.local/reports"),
    
    # Operational - OEM Manuals (5)
    ("GE Renewable Tech Docs", "https://www.ge-renewable.com/tech-docs"),
    ("Vestas Service Portal", "https://www.vestas.com/en/service"),
    ("Siemens Gamesa Support", "https://www.siemensgamesa.com/support"),
    ("Nordex Online Service", "https://www.nordex-online.com/en/service"),
    ("Enercon Support", "https://www.enercon.de/en/service"),
    
    # Operational - Safety & LOTO (4)
    ("OSHA Wind Energy", "https://www.osha.gov/wind-energy"),
    ("Global Wind Organisation", "https://www.gwo.org/"),
    ("NFPA 70E Arc Flash", "https://www.nfpa.org/70e"),
    ("ANSI Wind Standards", "https://www.ansi.org/wind"),
    
    # Junk / Entertainment (8)
    ("IGN Gaming News", "https://www.ign.com/"),
    ("DraftKings Sportsbook", "https://www.draftkings.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Steam Store", "https://store.steampowered.com/"),
    ("ESPN Live", "https://www.espn.com/"),
    ("Reddit - r/gaming", "https://www.reddit.com/r/gaming/"),
    ("Twitch.tv Streams", "https://www.twitch.tv/"),
    ("Hulu", "https://www.hulu.com/")
]

children = []
for i, (name, url) in enumerate(bookmarks_data):
    ts = str(chrome_base - (i + 1) * 6000000)
    children.append({
        "date_added": ts,
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base - 1000000000),
            "date_modified": str(chrome_base),
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
    json.dump(bookmarks, f, indent=3)
PYEOF

# Fix permissions
chown -R ga:ga /home/ga/.config/google-chrome/

# ── 4. Create the Specification Document ────────────────────────────────────
echo "Creating field laptop specification document..."
cat > /home/ga/Desktop/field_laptop_spec.txt << 'EOF'
================================================================================
BLUE RIDGE WIND FARM - FIELD LAPTOP CONFIGURATION STANDARD
Version: 2026.1
================================================================================

Technicians MUST configure their Toughbook browsers to the following standard 
prior to dispatch to the turbine sites.

1. BOOKMARK ORGANIZATION
   The browser currently contains bookmarks mixed with the previous intern's 
   personal links.
   - DELETE all entertainment/gaming/sports bookmarks (IGN, DraftKings, Netflix, 
     Steam, ESPN, Reddit, Twitch, Hulu).
   - Create exactly 4 folders on the Bookmark Bar:
     * "Weather & Forecasting"
     * "SCADA Control"
     * "OEM Manuals"
     * "Safety & LOTO"
   - Categorize all remaining operational bookmarks into their appropriate folders.

2. CHROME FLAGS FOR LOW-BANDWIDTH ENVIRONMENTS
   Access chrome://flags and configure:
   - "Offline Auto-Reload Mode" -> ENABLED (Allows SCADA tabs to auto-recover 
     when moving through cellular dead zones).
   - "Experimental QUIC protocol" -> DISABLED (Drops packets on our VPN).
   - "Smooth Scrolling" -> DISABLED (Causes jitter with rugged touchscreens).

3. DIAGNOSTIC SEARCH ENGINES
   Add custom search engines in Settings > Search engine > Manage search engines:
   - Search Engine: Fault DB
     Shortcut: fault
     URL: https://kb.blueridge-wind.local/search?fault_code=%s

   - Search Engine: Part Catalog
     Shortcut: part
     URL: https://parts.windoem.com/catalog?sku=%s

4. FIELD ACCESSIBILITY FONTS
   To ensure readability in high-glare environments and bumpy vehicles, go to 
   Appearance > Customize fonts:
   - Font size (Default): 22
   - Minimum font size: 16

5. STARTUP CONFIGURATION
   - On startup -> "Continue where you left off" (Preserves SCADA session 
     after a sudden reboot).

6. SAFETY DOCUMENT RETRIEVAL
   - Download the updated Lockout-Tagout procedure from our local field server:
     http://localhost:8080/LOTO_procedure_2026.pdf
   - Save the file to: ~/Documents/Field_Safety/
EOF
chown ga:ga /home/ga/Desktop/field_laptop_spec.txt

# ── 5. Generate target directory and local PDF server ───────────────────────
echo "Creating Field_Safety directory and local server..."
mkdir -p /home/ga/Documents/Field_Safety/
chown ga:ga /home/ga/Documents/Field_Safety/

mkdir -p /tmp/field_server
cat > /tmp/field_server/loto.txt << 'EOF'
Blue Ridge Wind Farm
LOTO (Lockout-Tagout) Procedure 2026

1. Identify all energy sources (electrical, mechanical, hydraulic).
2. Notify affected personnel.
3. Shut down turbine via SCADA and local control panel.
4. Isolate energy sources.
5. Apply lockout devices and tags.
6. Verify zero energy state (Test before you touch).
7. Perform maintenance.
EOF

# Convert text to realistic PDF using LibreOffice
sudo -u ga libreoffice --headless --convert-to pdf /tmp/field_server/loto.txt --outdir /tmp/field_server/ >/dev/null 2>&1
mv /tmp/field_server/loto.pdf /tmp/field_server/LOTO_procedure_2026.pdf

# Start background python HTTP server
cd /tmp/field_server
sudo -u ga python3 -m http.server 8080 > /dev/null 2>&1 &
cd - > /dev/null

# ── 6. Start Chrome ─────────────────────────────────────────────────────────
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" || true

# Wait for Chrome window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        break
    fi
    sleep 1
done

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="