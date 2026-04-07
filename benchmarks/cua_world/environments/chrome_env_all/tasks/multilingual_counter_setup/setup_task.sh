#!/bin/bash
set -euo pipefail

echo "=== Multilingual Counter Setup Task Setup ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Stop Chrome to prepare profile
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Prepare Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# 1. Create Bookmarks file (18 flat bookmarks)
echo "Creating initial bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

urls = [
    ("https://www.enterprise.com", "Enterprise"),
    ("https://www.hertz.com", "Hertz"),
    ("https://www.avis.com", "Avis"),
    ("https://www.sixt.com", "Sixt"),
    ("https://turo.com", "Turo"),
    ("https://www.geico.com", "GEICO"),
    ("https://www.progressive.com", "Progressive"),
    ("https://www.nhtsa.gov", "NHTSA"),
    ("https://www.flhsmv.gov", "FLHSMV"),
    ("https://www.visitflorida.com", "Visit Florida"),
    ("https://www.miamiandbeaches.com", "Miami Beaches"),
    ("https://www.tripadvisor.com", "TripAdvisor"),
    ("https://www.rae.es", "RAE"),
    ("https://www.spanishdict.com", "SpanishDict"),
    ("https://www.bbc.com/mundo", "BBC Mundo"),
    ("https://www.youtube.com", "YouTube"),
    ("https://www.espn.com", "ESPN"),
    ("https://www.reddit.com", "Reddit")
]

children = []
for i, (url, name) in enumerate(urls):
    children.append({
        "date_added": str(chrome_base - (20-i)*600000000),
        "guid": str(uuid.uuid4()),
        "id": str(i+5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0"*32,
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

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=2)
PYEOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"

# 2. Create basic Preferences (English only, default settings)
echo "Creating default Preferences..."
cat > "$CHROME_PROFILE/Preferences" << 'PREFEOF'
{
   "intl": {
      "accept_languages": "en-US,en"
   },
   "spellcheck": {
      "dictionaries": ["en-US"]
   },
   "translate": {
      "enabled": true
   },
   "translate_blocked_languages": [],
   "homepage_is_newtabpage": true,
   "session": {
      "restore_on_startup": 5
   },
   "profile": {
      "password_manager_enabled": true,
      "default_content_setting_values": {
         "cookies": 1
      }
   },
   "autofill": {
      "profile_enabled": true
   }
}
PREFEOF
chown ga:ga "$CHROME_PROFILE/Preferences"
cp "$CHROME_PROFILE/Preferences" /tmp/initial_prefs.json

# 3. Create spec document
echo "Creating configuration guide..."
cat > "/home/ga/Desktop/counter_terminal_config_guide.txt" << 'SPECEOF'
MIAMI INTERNATIONAL RENTALS
Counter Terminal Configuration Guide v1.4

1. LANGUAGE & TRANSLATION
- Preferred Languages: Add Spanish (Latin America) or generic Spanish to Chrome's languages alongside English.
- Spell-check: Enable spell-check dictionaries for BOTH English and Spanish.
- Translation: Enable Google Translate. English is our primary language, so set English to "Never translate". Ensure Spanish is NOT blocked from being translated (allow it to offer translation).

2. BOOKMARK ORGANIZATION
Organize the bookmarks bar into exactly four primary folders (with their respective links):
- "Fleet & Reservations": enterprise, hertz, avis, sixt, turo
- "Insurance & Compliance": geico, progressive, nhtsa, flhsmv
- "Tourism Partners": visitflorida, miamiandbeaches, tripadvisor
- "Personal": youtube, espn, reddit
Note: Place the Spanish resources (rae, spanishdict, bbc/mundo) into whichever folder you see fit, or create a fifth "Spanish Resources" folder for them.

3. CUSTOM SEARCH ENGINES
Add these site search shortcuts to Chrome:
- Keyword: vin -> URL: https://vpic.nhtsa.dot.gov/decoder/Decoder/%s
- Keyword: res -> URL: https://www.enterprise.com/en/reserve.html#%s
- Keyword: plate -> URL: https://services.flhsmv.gov/%s

4. STARTUP & DOWNLOADS
- Homepage: Set to https://www.enterprise.com and ensure the home button is enabled.
- On Startup: Configure Chrome to "Continue where you left off".
- Downloads: Set the default download location to ~/Documents/Rental_Agreements (create this folder if it doesn't exist).

5. PRIVACY & SECURITY
- Third-party cookies: Block third-party cookies.
- Credentials: Turn OFF "Offer to save passwords".
- Autofill: Turn OFF address and payment autofill.
SPECEOF
chown ga:ga "/home/ga/Desktop/counter_terminal_config_guide.txt"

# Create downloads folder
mkdir -p "/home/ga/Documents/Rental_Agreements"
chown ga:ga "/home/ga/Documents/Rental_Agreements"

# Launch Chrome
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 google-chrome --remote-debugging-port=9222 --start-maximized > /tmp/chrome_task.log 2>&1 &"
sleep 5

# Focus and Maximize
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="