#!/usr/bin/env bash
# set -euo pipefail

echo "=== Educational Content Curation Task Setup ==="
echo "Task: Configure shared classroom Chrome browser per Digital Learning Environment spec"

# Wait for environment to be ready
sleep 2

# Kill any running Chrome to safely modify profile
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3

# Set up Chrome profile directory
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"

# ============================================================
# Create Bookmarks with 35 bookmarks scattered FLAT on bookmark bar
# (no folders - the agent must organize them)
# ============================================================
echo "Creating initial bookmarks (flat, unorganized)..."
cat > "$CHROME_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "edcontent2026setup",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13370000000000000",
               "guid": "ed000000-0000-4000-a000-000000000001",
               "id": "5",
               "name": "Khan Academy",
               "type": "url",
               "url": "https://www.khanacademy.org"
            },
            {
               "date_added": "13370000000100000",
               "guid": "ed000000-0000-4000-a000-000000000002",
               "id": "6",
               "name": "Khan Academy Math",
               "type": "url",
               "url": "https://www.khanacademy.org/math"
            },
            {
               "date_added": "13370000000200000",
               "guid": "ed000000-0000-4000-a000-000000000003",
               "id": "7",
               "name": "Desmos Calculator",
               "type": "url",
               "url": "https://www.desmos.com/calculator"
            },
            {
               "date_added": "13370000000300000",
               "guid": "ed000000-0000-4000-a000-000000000004",
               "id": "8",
               "name": "GeoGebra",
               "type": "url",
               "url": "https://www.geogebra.org"
            },
            {
               "date_added": "13370000000400000",
               "guid": "ed000000-0000-4000-a000-000000000005",
               "id": "9",
               "name": "PhET Simulations",
               "type": "url",
               "url": "https://phet.colorado.edu"
            },
            {
               "date_added": "13370000000500000",
               "guid": "ed000000-0000-4000-a000-000000000006",
               "id": "10",
               "name": "Wolfram Alpha",
               "type": "url",
               "url": "https://www.wolframalpha.com"
            },
            {
               "date_added": "13370000000600000",
               "guid": "ed000000-0000-4000-a000-000000000007",
               "id": "11",
               "name": "NASA Education",
               "type": "url",
               "url": "https://www.nasa.gov/stem"
            },
            {
               "date_added": "13370000000700000",
               "guid": "ed000000-0000-4000-a000-000000000008",
               "id": "12",
               "name": "National Geographic Education",
               "type": "url",
               "url": "https://education.nationalgeographic.org"
            },
            {
               "date_added": "13370000000800000",
               "guid": "ed000000-0000-4000-a000-000000000009",
               "id": "13",
               "name": "Science Buddies",
               "type": "url",
               "url": "https://www.sciencebuddies.org"
            },
            {
               "date_added": "13370000000900000",
               "guid": "ed000000-0000-4000-a000-00000000000a",
               "id": "14",
               "name": "CK-12",
               "type": "url",
               "url": "https://www.ck12.org"
            },
            {
               "date_added": "13370000001000000",
               "guid": "ed000000-0000-4000-a000-00000000000b",
               "id": "15",
               "name": "CommonLit",
               "type": "url",
               "url": "https://www.commonlit.org"
            },
            {
               "date_added": "13370000001100000",
               "guid": "ed000000-0000-4000-a000-00000000000c",
               "id": "16",
               "name": "Newsela",
               "type": "url",
               "url": "https://newsela.com"
            },
            {
               "date_added": "13370000001200000",
               "guid": "ed000000-0000-4000-a000-00000000000d",
               "id": "17",
               "name": "ReadWorks",
               "type": "url",
               "url": "https://www.readworks.org"
            },
            {
               "date_added": "13370000001300000",
               "guid": "ed000000-0000-4000-a000-00000000000e",
               "id": "18",
               "name": "Storybird",
               "type": "url",
               "url": "https://storybird.com"
            },
            {
               "date_added": "13370000001400000",
               "guid": "ed000000-0000-4000-a000-00000000000f",
               "id": "19",
               "name": "PBS LearningMedia",
               "type": "url",
               "url": "https://www.pbslearningmedia.org"
            },
            {
               "date_added": "13370000001500000",
               "guid": "ed000000-0000-4000-a000-000000000010",
               "id": "20",
               "name": "iCivics",
               "type": "url",
               "url": "https://www.icivics.org"
            },
            {
               "date_added": "13370000001600000",
               "guid": "ed000000-0000-4000-a000-000000000011",
               "id": "21",
               "name": "Library of Congress",
               "type": "url",
               "url": "https://www.loc.gov"
            },
            {
               "date_added": "13370000001700000",
               "guid": "ed000000-0000-4000-a000-000000000012",
               "id": "22",
               "name": "Smithsonian Learning",
               "type": "url",
               "url": "https://learninglab.si.edu"
            },
            {
               "date_added": "13370000001800000",
               "guid": "ed000000-0000-4000-a000-000000000013",
               "id": "23",
               "name": "EDSITEment",
               "type": "url",
               "url": "https://edsitement.neh.gov"
            },
            {
               "date_added": "13370000001900000",
               "guid": "ed000000-0000-4000-a000-000000000014",
               "id": "24",
               "name": "Facing History",
               "type": "url",
               "url": "https://www.facinghistory.org"
            },
            {
               "date_added": "13370000002000000",
               "guid": "ed000000-0000-4000-a000-000000000015",
               "id": "25",
               "name": "Google Classroom",
               "type": "url",
               "url": "https://classroom.google.com"
            },
            {
               "date_added": "13370000002100000",
               "guid": "ed000000-0000-4000-a000-000000000016",
               "id": "26",
               "name": "Quizlet",
               "type": "url",
               "url": "https://quizlet.com"
            },
            {
               "date_added": "13370000002200000",
               "guid": "ed000000-0000-4000-a000-000000000017",
               "id": "27",
               "name": "Kahoot",
               "type": "url",
               "url": "https://kahoot.com"
            },
            {
               "date_added": "13370000002300000",
               "guid": "ed000000-0000-4000-a000-000000000018",
               "id": "28",
               "name": "Edpuzzle",
               "type": "url",
               "url": "https://edpuzzle.com"
            },
            {
               "date_added": "13370000002400000",
               "guid": "ed000000-0000-4000-a000-000000000019",
               "id": "29",
               "name": "Padlet",
               "type": "url",
               "url": "https://padlet.com"
            },
            {
               "date_added": "13370000002500000",
               "guid": "ed000000-0000-4000-a000-00000000001a",
               "id": "30",
               "name": "Canva Education",
               "type": "url",
               "url": "https://www.canva.com/education"
            },
            {
               "date_added": "13370000002600000",
               "guid": "ed000000-0000-4000-a000-00000000001b",
               "id": "31",
               "name": "Flipgrid",
               "type": "url",
               "url": "https://info.flip.com"
            },
            {
               "date_added": "13370000002700000",
               "guid": "ed000000-0000-4000-a000-00000000001c",
               "id": "32",
               "name": "Nearpod",
               "type": "url",
               "url": "https://nearpod.com"
            },
            {
               "date_added": "13370000002800000",
               "guid": "ed000000-0000-4000-a000-00000000001d",
               "id": "33",
               "name": "Seesaw",
               "type": "url",
               "url": "https://web.seesaw.me"
            },
            {
               "date_added": "13370000002900000",
               "guid": "ed000000-0000-4000-a000-00000000001e",
               "id": "34",
               "name": "ClassDojo",
               "type": "url",
               "url": "https://www.classdojo.com"
            },
            {
               "date_added": "13370000003000000",
               "guid": "ed000000-0000-4000-a000-00000000001f",
               "id": "35",
               "name": "Reddit",
               "type": "url",
               "url": "https://www.reddit.com"
            },
            {
               "date_added": "13370000003100000",
               "guid": "ed000000-0000-4000-a000-000000000020",
               "id": "36",
               "name": "TikTok",
               "type": "url",
               "url": "https://www.tiktok.com"
            },
            {
               "date_added": "13370000003200000",
               "guid": "ed000000-0000-4000-a000-000000000021",
               "id": "37",
               "name": "Twitter/X",
               "type": "url",
               "url": "https://x.com"
            },
            {
               "date_added": "13370000003300000",
               "guid": "ed000000-0000-4000-a000-000000000022",
               "id": "38",
               "name": "Twitch",
               "type": "url",
               "url": "https://www.twitch.tv"
            },
            {
               "date_added": "13370000003400000",
               "guid": "ed000000-0000-4000-a000-000000000023",
               "id": "39",
               "name": "Discord",
               "type": "url",
               "url": "https://discord.com"
            }
         ],
         "date_added": "13370000000000000",
         "date_modified": "13370000003400000",
         "guid": "ed000000-0000-4000-a000-000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13370000000000000",
         "date_modified": "0",
         "guid": "ed000000-0000-4000-b000-000000000001",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13370000000000000",
         "date_modified": "0",
         "guid": "ed000000-0000-4000-b000-000000000002",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
BOOKMARKS_EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "Created bookmarks file with 35 flat bookmarks on the bookmark bar"

# ============================================================
# Create Chrome Preferences with NON-COMPLIANT settings
# ============================================================
echo "Creating non-compliant Chrome Preferences..."
cat > "$CHROME_PROFILE/Preferences" << 'PREFS_EOF'
{
   "bookmark_bar": {
      "show_on_all_tabs": true
   },
   "browser": {
      "has_seen_welcome_page": true
   },
   "credentials_enable_service": true,
   "autofill": {
      "profile_enabled": true,
      "credit_card_enabled": true
   },
   "default_search_provider_data": {
      "template_url_data": {
         "keyword": "google.com",
         "short_name": "Google",
         "url": "https://www.google.com/search?q={searchTerms}"
      }
   },
   "download": {
      "default_directory": "/home/ga/Downloads",
      "prompt_for_download": false
   },
   "homepage": "https://www.google.com",
   "homepage_is_newtabpage": false,
   "profile": {
      "cookie_controls_mode": 0,
      "default_content_setting_values": {
         "notifications": 1
      },
      "password_manager_enabled": true
   },
   "safebrowsing": {
      "enabled": true,
      "enhanced": false
   },
   "session": {
      "restore_on_startup": 1,
      "startup_urls": []
   }
}
PREFS_EOF

chown ga:ga "$CHROME_PROFILE/Preferences"
echo "Created non-compliant Preferences:"
echo "  - No SafeSearch enforcement"
echo "  - No custom search engines"
echo "  - Homepage: google.com (wrong - should be classroom.google.com)"
echo "  - Download path: /home/ga/Downloads (wrong - should be Student_Resources)"
echo "  - No content restrictions configured"
echo "  - Password saving: ENABLED (should be disabled for shared browser)"
echo "  - Autofill: ENABLED (should be disabled)"
echo "  - Third-party cookies: ALLOWED (should be blocked)"
echo "  - Notifications: ALLOWED (should be blocked)"
echo "  - Safe browsing: Standard (should be Enhanced)"

# ============================================================
# Create the Digital Learning Environment specification
# ============================================================
echo "Creating Digital Learning Environment specification..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/digital_learning_spec.txt << 'SPEC_EOF'
UNIFIED SCHOOL DISTRICT #42
DIGITAL LEARNING ENVIRONMENT SPECIFICATION
Document: DLE-2026-003
Approved: 2026-02-20

PURPOSE: Configure shared classroom browsers to support educational
activities while maintaining appropriate content boundaries.

SECTION 1: BOOKMARK ORGANIZATION BY SUBJECT AREA

Organize ALL educational bookmarks into the following folder structure
on the Bookmark Bar:

1.1 "Mathematics & Science" folder:
    - All Khan Academy bookmarks
    - Desmos Calculator
    - GeoGebra
    - PhET Simulations
    - Wolfram Alpha
    - NASA Education
    - National Geographic Education
    - Science Buddies
    - CK-12

1.2 "Language Arts & Humanities" folder:
    - CommonLit
    - Newsela
    - ReadWorks
    - Storybird
    - PBS LearningMedia
    - EDSITEment
    - Facing History

1.3 "Social Studies & Civics" folder:
    - iCivics
    - Library of Congress
    - Smithsonian Learning

1.4 "Classroom Tools" folder:
    - Google Classroom
    - Quizlet
    - Kahoot
    - Edpuzzle
    - Padlet
    - Canva Education
    - Flipgrid
    - Nearpod
    - Seesaw
    - ClassDojo

1.5 "Restricted - Teacher Only" folder:
    - Move Reddit, TikTok, Twitter/X, Twitch, and Discord here
    - These sites should also be blocked (see Section 4)

SECTION 2: EDUCATIONAL SEARCH SHORTCUTS

Configure these search engine shortcuts:

2.1 Keyword: "learn" - URL: https://www.khanacademy.org/search?referer=%2F&page_search_query=%s
    Name: "Khan Academy Search"

2.2 Keyword: "wiki" - URL: https://en.wikipedia.org/w/index.php?search=%s
    Name: "Wikipedia Search"

2.3 Keyword: "pbs" - URL: https://www.pbslearningmedia.org/search/?q=%s
    Name: "PBS LearningMedia Search"

SECTION 3: HOMEPAGE AND STARTUP

3.1 Homepage: https://classroom.google.com
3.2 On startup, open these pages:
    - https://classroom.google.com
    - https://www.khanacademy.org

SECTION 4: CONTENT SAFETY

4.1 Block third-party cookies
4.2 Block notifications from all sites by default
4.3 Block the following sites via Chrome site settings:
    - reddit.com
    - tiktok.com
    - x.com
    - twitch.tv
    - discord.com
4.4 Safe Browsing: Enhanced Protection

SECTION 5: DOWNLOAD MANAGEMENT

5.1 Default download directory: /home/ga/Documents/Student_Resources
5.2 Always ask where to save files: ENABLED

SECTION 6: AUTHENTICATION SECURITY (Shared Browser)

6.1 Password saving: DISABLED (shared device)
6.2 Address autofill: DISABLED
6.3 Payment methods: DISABLED
SPEC_EOF

chown ga:ga /home/ga/Desktop/digital_learning_spec.txt
echo "Created specification at ~/Desktop/digital_learning_spec.txt"

# ============================================================
# Create Student_Resources directory
# ============================================================
mkdir -p /home/ga/Documents/Student_Resources
chown -R ga:ga /home/ga/Documents/Student_Resources
echo "Created /home/ga/Documents/Student_Resources directory"

# ============================================================
# Record baseline state for verification
# ============================================================
echo "Recording baseline state..."
cat > /tmp/educational_content_curation_baseline.json << 'BASELINE_EOF'
{
   "task": "educational_content_curation",
   "baseline": {
      "bookmarks_flat_count": 35,
      "bookmark_folders": 0,
      "homepage": "https://www.google.com",
      "download_path": "/home/ga/Downloads",
      "prompt_for_download": false,
      "password_saving": true,
      "autofill_enabled": true,
      "cookie_controls_mode": 0,
      "notifications_default": 1,
      "safe_browsing_enhanced": false,
      "custom_search_engines": 0,
      "startup_urls": []
   },
   "expected": {
      "bookmark_folders": ["Mathematics & Science", "Language Arts & Humanities", "Social Studies & Civics", "Classroom Tools", "Restricted - Teacher Only"],
      "homepage": "https://classroom.google.com",
      "download_path": "/home/ga/Documents/Student_Resources",
      "prompt_for_download": true,
      "password_saving": false,
      "autofill_enabled": false,
      "cookie_controls_mode": 1,
      "notifications_default": 2,
      "safe_browsing_enhanced": true,
      "search_engine_keywords": ["learn", "wiki", "pbs"],
      "startup_urls": ["https://classroom.google.com", "https://www.khanacademy.org"]
   }
}
BASELINE_EOF

echo "Baseline recorded at /tmp/educational_content_curation_baseline.json"

# ============================================================
# Relaunch Chrome to about:blank
# ============================================================
echo "Launching Chrome..."
chown -R ga:ga "/home/ga/.config/google-chrome"
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# Focus Chrome window
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "Chrome CDP is accessible"
else
    echo "Warning: Chrome CDP not responding"
fi

# Take initial screenshot
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot saved"
fi

echo "=== Setup complete ==="
echo ""
echo "Chrome is ready with 35 flat bookmarks and non-compliant settings."
echo "The Digital Learning Environment specification is at ~/Desktop/digital_learning_spec.txt"
echo ""
echo "Agent must:"
echo "  1. Read the specification file"
echo "  2. Organize 35 bookmarks into 5 subject-area folders"
echo "  3. Add 3 educational search engine shortcuts"
echo "  4. Set homepage and startup pages"
echo "  5. Configure content safety (cookies, notifications, safe browsing)"
echo "  6. Set download directory and enable download prompt"
echo "  7. Disable password saving, autofill, and payment methods"
