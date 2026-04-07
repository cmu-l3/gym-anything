#!/usr/bin/env bash
# set -euo pipefail

echo "=== Factory Inspection Terminal Configuration Setup ==="
echo "Task: Configure Chrome per Factory Floor Workstation Standard"

# Wait for environment to be ready
sleep 2

# Kill running Chrome to safely construct the profile
echo "Stopping Chrome..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Setup Chrome profile directories
CHROME_CDP_PROFILE="/home/ga/.config/google-chrome-cdp"
mkdir -p "$CHROME_CDP_PROFILE/Default"
chown -R ga:ga "$CHROME_CDP_PROFILE"

CHROME_DEFAULT_PROFILE="/home/ga/.config/google-chrome"
mkdir -p "$CHROME_DEFAULT_PROFILE/Default"
chown -R ga:ga "$CHROME_DEFAULT_PROFILE"

# Setup required download directory
mkdir -p "/home/ga/Documents/Inspection_Reports"
chown ga:ga "/home/ga/Documents/Inspection_Reports"

# Generate bookmarks via Python to ensure valid JSON structure
echo "Generating Bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

# 32 Unorganized Bookmarks
bookmarks_list = [
    ("asq.org", "ASQ"),
    ("iso.org", "ISO Standards"),
    ("nist.gov/quality", "NIST Quality"),
    ("astm.org", "ASTM International"),
    ("asme.org", "ASME"),
    ("ipc.org", "IPC Electronics"),
    ("digikey.com", "DigiKey"),
    ("mouser.com", "Mouser Electronics"),
    ("arrow.com", "Arrow Electronics"),
    ("thomasnet.com", "ThomasNet"),
    ("octopart.com", "Octopart"),
    ("lcsc.com", "LCSC"),
    ("osha.gov", "OSHA"),
    ("nfpa.org", "NFPA"),
    ("ul.com", "UL"),
    ("ansi.org", "ANSI"),
    ("cpsc.gov", "CPSC"),
    ("sme.org", "SME"),
    ("themanufacturinginstitute.org", "Manufacturing Institute"),
    ("industryweek.com", "IndustryWeek"),
    ("automationworld.com", "Automation World"),
    ("qualitymag.com", "Quality Magazine"),
    ("pqndt.com", "NDT Resource"),
    ("sixsigmaonline.org", "Six Sigma"),
    ("lean.org", "Lean Enterprise"),
    ("youtube.com", "YouTube"),
    ("reddit.com", "Reddit"),
    ("facebook.com", "Facebook"),
    ("twitter.com", "Twitter"),
    ("instagram.com", "Instagram"),
    ("espn.com", "ESPN"),
    ("netflix.com", "Netflix")
]

children = []
for i, (domain, name) in enumerate(bookmarks_list):
    children.append({
        "date_added": str(chrome_base - (i + 1) * 600000000),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": f"https://www.{domain}/" if "nist.gov" not in domain else f"https://{domain}/"
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": "13360000000000000",
            "date_modified": "13360000000000000",
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {
            "children": [], "id": "2", "name": "Other bookmarks", "type": "folder"
        },
        "synced": {
            "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"
        }
    },
    "version": 1
}

# Write to both common profile locations
for path in ["/home/ga/.config/google-chrome/Default/Bookmarks", "/home/ga/.config/google-chrome-cdp/Default/Bookmarks"]:
    with open(path, "w") as f:
        json.dump(bookmarks, f)
    os.chown(path, 1000, 1000)
PYEOF

# Create Non-compliant Preferences
echo "Generating Preferences..."
cat > /tmp/default_prefs.json << 'PREF_EOF'
{
   "browser": {
      "show_home_button": true,
      "check_default_browser": false
   },
   "homepage": "https://www.google.com",
   "homepage_is_newtabpage": false,
   "webkit": {
      "webprefs": {
         "default_font_size": 16,
         "minimum_font_size": 0
      }
   },
   "session": {
      "restore_on_startup": 5
   },
   "download": {
      "default_directory": "/home/ga/Downloads",
      "prompt_for_download": false
   },
   "profile": {
      "password_manager_enabled": true,
      "default_content_setting_values": {
         "cookies": 1,
         "notifications": 1
      }
   },
   "autofill": {
      "profile_enabled": true,
      "credit_card_enabled": true
   },
   "safebrowsing": {
      "enabled": true
   }
}
PREF_EOF

cp /tmp/default_prefs.json "$CHROME_DEFAULT_PROFILE/Default/Preferences"
cp /tmp/default_prefs.json "$CHROME_CDP_PROFILE/Default/Preferences"
chown ga:ga "$CHROME_DEFAULT_PROFILE/Default/Preferences"
chown ga:ga "$CHROME_CDP_PROFILE/Default/Preferences"

# Create Non-compliant Local State (without required flags)
echo "Generating Local State..."
cat > /tmp/local_state.json << 'STATE_EOF'
{
   "browser": {
      "enabled_labs_experiments": []
   }
}
STATE_EOF

cp /tmp/local_state.json "$CHROME_DEFAULT_PROFILE/Local State"
cp /tmp/local_state.json "$CHROME_CDP_PROFILE/Local State"
chown ga:ga "$CHROME_DEFAULT_PROFILE/Local State"
chown ga:ga "$CHROME_CDP_PROFILE/Local State"

# Create Specification Document
echo "Creating specification document..."
cat > /home/ga/Desktop/factory_workstation_standard.txt << 'SPEC_EOF'
FACTORY FLOOR WORKSTATION STANDARD
Document: FWS-2025-011
Division: Electronics Assembly

All shared inspection terminals must be configured with the following Chrome settings.

1. BOOKMARK ORGANIZATION
Organize bookmarks into exactly 5 folders on the bookmark bar:
- "Quality & Standards" (Include ASQ, ISO, NIST, ASTM, ASME, IPC)
- "Components & Suppliers" (Include DigiKey, Mouser, Arrow, ThomasNet, Octopart, LCSC)
- "Safety & Compliance" (Include OSHA, NFPA, UL, ANSI, CPSC)
- "Manufacturing Resources" (Include SME, Manufacturing Institute, IndustryWeek, Automation World, Quality Magazine, NDT Resource, Six Sigma, Lean Enterprise)
- "Blocked - Personal" (Quarantine YouTube, Reddit, Facebook, Twitter, Instagram, ESPN, Netflix here)

2. TERMINAL PERFORMANCE FLAGS (chrome://flags)
To optimize performance on low-power inspection terminals, enable:
- Smooth Scrolling
- Tab Scrolling
- Back-forward Cache

3. READABILITY SETTINGS (Settings > Appearance)
Due to viewing distance on the factory floor:
- Font size must be set to "Large" or Custom (Default: 20)
- Minimum font size must be at least 14

4. STARTUP AND HOMEPAGE
- Homepage: https://www.asq.org
- On startup, open these specific pages: asq.org, osha.gov, digikey.com

5. SEARCH SHORTCUTS (Settings > Search engine > Manage search engines)
Add these site search shortcuts:
- Keyword "parts": https://www.digikey.com/en/products/result?keywords=%s
- Keyword "spec": https://www.astm.org/search/?query=%s
- Keyword "msds": https://www.fishersci.com/us/en/catalog/search/sdshome.html?keyword=%s

6. PRIVACY AND DOWNLOADS
- Download location: /home/ga/Documents/Inspection_Reports
- Ask where to save each file before downloading: Enabled
- Block third-party cookies: Enabled
- Default notification behavior: Don't allow sites to send notifications
- Safe Browsing: Enhanced Protection
- Save passwords: Disabled
- Save and fill addresses: Disabled
- Save and fill payment methods: Disabled
SPEC_EOF
chown ga:ga /home/ga/Desktop/factory_workstation_standard.txt

# Record anti-gaming setup timestamp
date +%s > /tmp/task_start_time.txt

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh &"
sleep 5

# Wait for Chrome window and maximize it
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        echo "Chrome window detected."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Capture Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="