#!/bin/bash
echo "=== Setting up Investigative OPSEC Workspace Task ==="

# Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# Ensure Secure_Vault directory exists
mkdir -p /home/ga/Documents/Secure_Vault
chown ga:ga /home/ga/Documents/Secure_Vault

# Create the OPSEC Protocol document
cat > /home/ga/Desktop/opsec_protocol.txt << 'EOF'
INVESTIGATIVE OPSEC PROTOCOL - WORKSTATION PREP

1. BOOKMARK ORGANIZATION
Create the following folders on your bookmark bar and sort your research links:
- "Secure Comms"
- "Public Records"
- "Target Intel"
- "News Outlets"

2. SANITIZATION
Permanently delete ALL personal site bookmarks (Netflix, Hulu, Facebook, Instagram, Twitter) from the browser to prevent account contamination.

3. HARDWARE & PERMISSIONS
Navigate to Chrome Site Settings and set the default behavior for the following to "Don't allow sites to use..." (Block):
- Location
- Camera
- Microphone
- Background Sync

4. PRIVACY & TELEMETRY
- Block third-party cookies.
- Send a "Do Not Track" request with your browsing traffic.
- Disable "Safe Browsing" (Set to "No protection" to prevent URL telemetry).

5. SEARCH ENGINES
Add two custom search engines for rapid OSINT queries:
- Keyword: pacer | URL: https://hconnect.pacer.uscourts.gov/h/search?q=%s
- Keyword: offshore | URL: https://offshoreleaks.icij.org/search?q=%s

6. DOWNLOAD SECURITY
- Change the default download location to: /home/ga/Documents/Secure_Vault
- Enable the toggle to "Ask where to save each file before downloading".
EOF
chown ga:ga /home/ga/Desktop/opsec_protocol.txt

# Stop any running Chrome instances
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# Generate Bookmarks JSON with 25 flat bookmarks
echo "Generating flat bookmarks..."
python3 << 'PYEOF'
import json, time, uuid

chrome_base = (int(time.time()) + 11644473600) * 1000000

sites = [
    # Secure Comms
    ("Proton Mail", "https://proton.me/mail"),
    ("Signal", "https://signal.org/"),
    ("SecureDrop", "https://securedrop.org/"),
    ("Tor Project", "https://www.torproject.org/"),
    ("Wire", "https://wire.com/"),
    # Public Records
    ("PACER", "https://pacer.login.uscourts.gov/"),
    ("FOIA.gov", "https://www.foia.gov/"),
    ("OpenSecrets", "https://www.opensecrets.org/"),
    ("FEC Data", "https://www.fec.gov/data/"),
    ("LittleSis", "https://littlesis.org/"),
    # Target Intel
    ("FlightRadar24", "https://www.flightradar24.com/"),
    ("VesselFinder", "https://www.vesselfinder.com/"),
    ("OpenCorporates", "https://opencorporates.com/"),
    ("Offshore Leaks", "https://offshoreleaks.icij.org/"),
    ("WikiLeaks Search", "https://search.wikileaks.org/"),
    # News Outlets
    ("AP News", "https://apnews.com/"),
    ("Reuters", "https://www.reuters.com/"),
    ("ProPublica", "https://www.propublica.org/"),
    ("ICIJ", "https://www.icij.org/"),
    ("Bellingcat", "https://www.bellingcat.com/"),
    # Personal Sites (To be purged)
    ("Netflix", "https://www.netflix.com/"),
    ("Hulu", "https://www.hulu.com/"),
    ("Facebook", "https://www.facebook.com/"),
    ("Instagram", "https://www.instagram.com/"),
    ("Twitter", "https://twitter.com/")
]

children = []
for i, (name, url) in enumerate(sites):
    children.append({
        "date_added": str(chrome_base - (i * 600000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "initial_opsec_state",
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base - 86400000000),
            "date_modified": "0",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [],
            "date_added": str(chrome_base - 86400000000),
            "date_modified": "0",
            "id": "2",
            "name": "Other bookmarks",
            "type": "folder"
        },
        "synced": {
            "children": [],
            "date_added": str(chrome_base - 86400000000),
            "date_modified": "0",
            "id": "3",
            "name": "Mobile bookmarks",
            "type": "folder"
        }
    },
    "version": 1
}

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="