#!/bin/bash
set -e
echo "=== Setting up assistive_browser_setup task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specification file
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/at_browser_spec.txt << 'SPECEOF'
=============================================================
   ASSISTIVE TECHNOLOGY BROWSER CONFIGURATION SPECIFICATION
   Prepared by: Sarah Chen, OTR/L — Low Vision Rehabilitation
   Client ID: LV-2026-0047
   Date: 2026-01-15
   Review Date: 2026-07-15
=============================================================

SECTION 1: FONT AND DISPLAY SETTINGS
-------------------------------------
The client has been assessed with best-corrected visual acuity of
20/200 in the better eye. The following display settings are
prescribed to maximize legibility:

  - Default (proportional) font size: 24
  - Fixed-width (monospace) font size: 20
  - Minimum font size: 16
  - Default page zoom: 150%

SECTION 2: BOOKMARK ORGANIZATION
----------------------------------
Organize the 30 existing bookmarks into exactly five (5) folders:

  Folder 1: "Assistive Technology"
    - NVDA Screen Reader, Freedom Scientific, American Printing House,
      American Foundation for the Blind, Bookshare, Learning Ally,
      Be My Eyes, AbleNet

  Folder 2: "Health & Wellness"
    - WebMD, Mayo Clinic, CDC, NIH, MedlinePlus, Care Compare

  Folder 3: "Daily Living"
    - Amazon, Instacart, DoorDash, USPS, UPS, Chase Bank

  Folder 4: "Entertainment"
    - YouTube, Spotify, NPR, Facebook, Zoom

  Folder 5: "Government Services"
    - Social Security, Medicare, Veterans Affairs, USA.gov, Benefits.gov

No bookmarks should remain loose on the bar.

SECTION 3: SEARCH ENGINE SHORTCUTS
------------------------------------
  Keyword: yt
  URL Template: https://www.youtube.com/results?search_query=%s

  Keyword: amz
  URL Template: https://www.amazon.com/s?k=%s

SECTION 4: HOMEPAGE AND STARTUP
---------------------------------
  Homepage: https://www.afb.org
  On startup, open these specific pages:
    - https://www.afb.org
    - https://www.google.com

SECTION 5: PRIVACY AND SECURITY
---------------------------------
  - Block third-party cookies
  - Disable password saving
  - Disable address autofill
  - Disable payment method autofill

SECTION 6: DOWNLOADS
----------------------
  Download directory: /home/ga/Documents/Client_Downloads
  Always ask where to save files: YES

SECTION 7: DESKTOP SHORTCUT
------------------------------
Create a Linux desktop shortcut file at ~/Desktop/Accessible_Chrome.desktop
  - Valid freedesktop .desktop file
  - Name=Accessible Chrome
  - Launch Chrome (google-chrome-stable) with flags:
      --force-renderer-accessibility
      --enable-caret-browsing
  - Type=Application
=============================================================
END OF SPECIFICATION
=============================================================
SPECEOF
chown ga:ga /home/ga/Desktop/at_browser_spec.txt

# Create download directory
mkdir -p /home/ga/Documents/Client_Downloads
chown ga:ga /home/ga/Documents/Client_Downloads

# Remove any pre-existing desktop shortcut
rm -f /home/ga/Desktop/Accessible_Chrome.desktop

# Stop Chrome to prepare profile safely
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true
sleep 1

# Ensure Chrome CDP profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome-cdp

# Write the initial 30 flat bookmarks using python for valid JSON
python3 << 'PYEOF'
import json

bookmarks_list = [
    ("NVDA Screen Reader", "https://www.nvaccess.org"),
    ("Freedom Scientific", "https://www.freedomscientific.com"),
    ("American Printing House", "https://www.aph.org"),
    ("American Foundation for the Blind", "https://www.afb.org"),
    ("Bookshare", "https://www.bookshare.org"),
    ("Learning Ally", "https://www.learningally.org"),
    ("Be My Eyes", "https://www.bemyeyes.com"),
    ("AbleNet", "https://www.ablenetinc.com"),
    ("WebMD", "https://www.webmd.com"),
    ("Mayo Clinic", "https://www.mayoclinic.org"),
    ("CDC", "https://www.cdc.gov"),
    ("NIH", "https://www.nih.gov"),
    ("MedlinePlus", "https://medlineplus.gov"),
    ("Care Compare", "https://www.medicare.gov/care-compare"),
    ("Amazon", "https://www.amazon.com"),
    ("Instacart", "https://www.instacart.com"),
    ("DoorDash", "https://www.doordash.com"),
    ("USPS", "https://www.usps.com"),
    ("UPS", "https://www.ups.com"),
    ("Chase Bank", "https://www.chase.com"),
    ("YouTube", "https://www.youtube.com"),
    ("Spotify", "https://open.spotify.com"),
    ("NPR", "https://www.npr.org"),
    ("Facebook", "https://www.facebook.com"),
    ("Zoom", "https://zoom.us"),
    ("Social Security", "https://www.ssa.gov"),
    ("Medicare", "https://www.medicare.gov"),
    ("Veterans Affairs", "https://www.va.gov"),
    ("USA.gov", "https://www.usa.gov"),
    ("Benefits.gov", "https://www.benefits.gov")
]

children = []
for i, (name, url) in enumerate(bookmarks_list):
    children.append({
        "date_added": "13350000000000000",
        "id": str(i + 4),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
   "checksum": "",
   "roots": {
      "bookmark_bar": {
         "children": children,
         "date_added": "13000000000000000",
         "date_modified": "13350000000000030",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": { "children": [], "id": "2", "name": "Other bookmarks", "type": "folder" },
      "synced": { "children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder" }
   },
   "version": 1
}

with open("/home/ga/.config/google-chrome-cdp/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Record initial bookmark state for anti-gaming
cp "$CHROME_PROFILE/Bookmarks" /tmp/initial_bookmarks.json 2>/dev/null || true

# Set default (non-compliant) preferences
cat > "$CHROME_PROFILE/Preferences" << 'PREFEOF'
{
   "profile": {
      "password_manager_enabled": true,
      "default_zoom_level": 0.0
   },
   "browser": {
      "show_home_button": true
   },
   "homepage": "https://www.google.com",
   "homepage_is_newtabpage": false,
   "download": {
      "prompt_for_download": false,
      "default_directory": "/home/ga/Downloads"
   },
   "webkit": {
      "webprefs": {
         "default_font_size": 16,
         "default_fixed_font_size": 13,
         "minimum_font_size": 0
      }
   },
   "autofill": {
      "enabled": true,
      "profile_enabled": true,
      "credit_card_enabled": true
   },
   "session": {
      "restore_on_startup": 5
   }
}
PREFEOF
chown ga:ga "$CHROME_PROFILE/Preferences"

# Record initial preferences for anti-gaming
cp "$CHROME_PROFILE/Preferences" /tmp/initial_preferences.json 2>/dev/null || true

# Start Chrome in the background
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank &"
sleep 5

# Maximize Chrome window
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take screenshot of initial state
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="