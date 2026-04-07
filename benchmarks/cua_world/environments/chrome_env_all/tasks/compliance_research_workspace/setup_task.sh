#!/usr/bin/env bash
# set -euo pipefail

echo "=== Compliance Research Workspace Task Setup ==="
echo "Task: Implement Browser Configuration Standard for Regulatory Affairs"

# Wait for environment to be ready
sleep 2

# Stop Chrome if running to modify profile safely
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# ============================================================
# Create Bookmarks file with 25 regulatory bookmarks FLAT
# (no folders - agent must organize them)
# ============================================================
echo "Creating flat bookmark bar with 25 regulatory bookmarks..."
cat > "$CHROME_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "compliance_task_initial_state",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "guid": "c0000000-0000-4000-a000-000000000001",
               "id": "5",
               "name": "FDA Home",
               "type": "url",
               "url": "https://www.fda.gov/"
            },
            {
               "date_added": "13360799520000000",
               "guid": "c0000000-0000-4000-a000-000000000002",
               "id": "6",
               "name": "FDA Drugs",
               "type": "url",
               "url": "https://www.fda.gov/drugs"
            },
            {
               "date_added": "13360799530000000",
               "guid": "c0000000-0000-4000-a000-000000000003",
               "id": "7",
               "name": "FDA Medical Devices",
               "type": "url",
               "url": "https://www.fda.gov/medical-devices"
            },
            {
               "date_added": "13360799540000000",
               "guid": "c0000000-0000-4000-a000-000000000004",
               "id": "8",
               "name": "EPA Home",
               "type": "url",
               "url": "https://www.epa.gov/"
            },
            {
               "date_added": "13360799550000000",
               "guid": "c0000000-0000-4000-a000-000000000005",
               "id": "9",
               "name": "EPA Laws & Regulations",
               "type": "url",
               "url": "https://www.epa.gov/laws-regulations"
            },
            {
               "date_added": "13360799560000000",
               "guid": "c0000000-0000-4000-a000-000000000006",
               "id": "10",
               "name": "EPA Compliance",
               "type": "url",
               "url": "https://www.epa.gov/compliance"
            },
            {
               "date_added": "13360799570000000",
               "guid": "c0000000-0000-4000-a000-000000000007",
               "id": "11",
               "name": "OSHA Home",
               "type": "url",
               "url": "https://www.osha.gov/"
            },
            {
               "date_added": "13360799580000000",
               "guid": "c0000000-0000-4000-a000-000000000008",
               "id": "12",
               "name": "OSHA Laws & Regs",
               "type": "url",
               "url": "https://www.osha.gov/laws-regs"
            },
            {
               "date_added": "13360799590000000",
               "guid": "c0000000-0000-4000-a000-000000000009",
               "id": "13",
               "name": "SEC Home",
               "type": "url",
               "url": "https://www.sec.gov/"
            },
            {
               "date_added": "13360799600000000",
               "guid": "c0000000-0000-4000-a000-000000000010",
               "id": "14",
               "name": "SEC EDGAR",
               "type": "url",
               "url": "https://www.sec.gov/edgar"
            },
            {
               "date_added": "13360799610000000",
               "guid": "c0000000-0000-4000-a000-000000000011",
               "id": "15",
               "name": "NIST Home",
               "type": "url",
               "url": "https://www.nist.gov/"
            },
            {
               "date_added": "13360799620000000",
               "guid": "c0000000-0000-4000-a000-000000000012",
               "id": "16",
               "name": "NIST Cybersecurity Framework",
               "type": "url",
               "url": "https://www.nist.gov/cyberframework"
            },
            {
               "date_added": "13360799630000000",
               "guid": "c0000000-0000-4000-a000-000000000013",
               "id": "17",
               "name": "EUR-Lex",
               "type": "url",
               "url": "https://eur-lex.europa.eu/"
            },
            {
               "date_added": "13360799640000000",
               "guid": "c0000000-0000-4000-a000-000000000014",
               "id": "18",
               "name": "EU Law",
               "type": "url",
               "url": "https://ec.europa.eu/info/law"
            },
            {
               "date_added": "13360799650000000",
               "guid": "c0000000-0000-4000-a000-000000000015",
               "id": "19",
               "name": "WHO Home",
               "type": "url",
               "url": "https://www.who.int/"
            },
            {
               "date_added": "13360799660000000",
               "guid": "c0000000-0000-4000-a000-000000000016",
               "id": "20",
               "name": "WHO Publications",
               "type": "url",
               "url": "https://www.who.int/publications"
            },
            {
               "date_added": "13360799670000000",
               "guid": "c0000000-0000-4000-a000-000000000017",
               "id": "21",
               "name": "ISO Standards",
               "type": "url",
               "url": "https://www.iso.org/"
            },
            {
               "date_added": "13360799680000000",
               "guid": "c0000000-0000-4000-a000-000000000018",
               "id": "22",
               "name": "Federal Register",
               "type": "url",
               "url": "https://www.federalregister.gov/"
            },
            {
               "date_added": "13360799690000000",
               "guid": "c0000000-0000-4000-a000-000000000019",
               "id": "23",
               "name": "Regulations.gov",
               "type": "url",
               "url": "https://www.regulations.gov/"
            },
            {
               "date_added": "13360799700000000",
               "guid": "c0000000-0000-4000-a000-000000000020",
               "id": "24",
               "name": "Congress.gov",
               "type": "url",
               "url": "https://www.congress.gov/"
            },
            {
               "date_added": "13360799710000000",
               "guid": "c0000000-0000-4000-a000-000000000021",
               "id": "25",
               "name": "GovInfo",
               "type": "url",
               "url": "https://www.govinfo.gov/"
            },
            {
               "date_added": "13360799720000000",
               "guid": "c0000000-0000-4000-a000-000000000022",
               "id": "26",
               "name": "CPSC Home",
               "type": "url",
               "url": "https://www.cpsc.gov/"
            },
            {
               "date_added": "13360799730000000",
               "guid": "c0000000-0000-4000-a000-000000000023",
               "id": "27",
               "name": "FTC Home",
               "type": "url",
               "url": "https://www.ftc.gov/"
            },
            {
               "date_added": "13360799740000000",
               "guid": "c0000000-0000-4000-a000-000000000024",
               "id": "28",
               "name": "DOJ Home",
               "type": "url",
               "url": "https://www.justice.gov/"
            }
         ],
         "date_added": "13360799500000000",
         "date_modified": "13360799740000000",
         "guid": "c0000000-0000-4000-a000-000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "c0000000-0000-4000-b000-000000000001",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "c0000000-0000-4000-b000-000000000002",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
BOOKMARKS_EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "Created bookmarks file with 24 flat regulatory bookmarks on bookmark bar"

# ============================================================
# Create Chrome Preferences file with NON-COMPLIANT settings
# ============================================================
echo "Creating non-compliant Chrome Preferences..."
cat > "$CHROME_PROFILE/Preferences" << 'PREFS_EOF'
{
   "bookmark_bar": {
      "show_on_all_tabs": true
   },
   "browser": {
      "has_seen_welcome_page": true,
      "show_home_button": true
   },
   "homepage": "https://www.google.com/",
   "homepage_is_newtabpage": false,
   "session": {
      "restore_on_startup": 1,
      "startup_urls": []
   },
   "download": {
      "default_directory": "/home/ga/Downloads",
      "prompt_for_download": false
   },
   "credentials_enable_service": true,
   "credentials_enable_autosignin": true,
   "autofill": {
      "profile_enabled": true,
      "credit_card_enabled": true
   },
   "profile": {
      "default_content_setting_values": {
         "cookies": 1
      },
      "block_third_party_cookies": false,
      "password_manager_enabled": true
   },
   "enable_do_not_track": false,
   "safebrowsing": {
      "enabled": true,
      "enhanced": false
   },
   "search_provider_overrides": [],
   "default_search_provider_data": {
      "template_url_data": []
   }
}
PREFS_EOF

chown ga:ga "$CHROME_PROFILE/Preferences"
echo "Created non-compliant Preferences (wrong homepage, no search engines, cookies allowed, etc.)"

# ============================================================
# Create the Browser Configuration Standard document
# ============================================================
echo "Creating Browser Configuration Standard document..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/browser_config_standard.txt << 'STANDARD_EOF'
DEPARTMENT OF REGULATORY AFFAIRS
BROWSER CONFIGURATION STANDARD v2.1
Effective Date: 2026-03-01
Classification: INTERNAL USE ONLY

1. BOOKMARK ORGANIZATION
   All regulatory bookmarks must be organized into the following folder hierarchy on the Bookmark Bar:

   1.1 "Federal Agencies" folder containing:
       - Sub-folder "FDA" with all FDA-related bookmarks
       - Sub-folder "EPA" with all EPA-related bookmarks
       - Sub-folder "OSHA" with all OSHA-related bookmarks
       - Sub-folder "SEC" with all SEC-related bookmarks

   1.2 "Standards Bodies" folder containing:
       - All NIST bookmarks
       - All ISO bookmarks

   1.3 "International" folder containing:
       - All EU-related bookmarks (eur-lex, ec.europa.eu)
       - All WHO bookmarks

   1.4 "Legislative Resources" folder containing:
       - Federal Register
       - Regulations.gov
       - Congress.gov
       - GovInfo (govinfo.gov)

   1.5 "Consumer Protection" folder containing:
       - CPSC bookmarks
       - FTC bookmarks
       - DOJ bookmarks

2. CUSTOM SEARCH ENGINE SHORTCUTS
   Configure the following search engine shortcuts:

   2.1 Keyword: "cfr" - URL: https://www.ecfr.gov/search?query=%s
       Name: "Code of Federal Regulations Search"

   2.2 Keyword: "fr" - URL: https://www.federalregister.gov/documents/search?conditions[term]=%s
       Name: "Federal Register Search"

   2.3 Keyword: "edgar" - URL: https://efts.sec.gov/LATEST/search-index?q=%s
       Name: "SEC EDGAR Search"

3. HOMEPAGE AND STARTUP
   3.1 Homepage: https://www.federalregister.gov
   3.2 On startup, open these pages:
       - https://www.federalregister.gov
       - https://www.regulations.gov
       - https://www.ecfr.gov

4. PRIVACY AND SECURITY
   4.1 Block third-party cookies
   4.2 Send "Do Not Track" requests: ENABLED
   4.3 Safe Browsing: Enhanced Protection mode

5. DOWNLOAD PREFERENCES
   5.1 Default download directory: /home/ga/Documents/Regulatory_Downloads
   5.2 Always ask where to save files: ENABLED

6. AUTOFILL AND PASSWORDS
   6.1 Password saving: DISABLED
   6.2 Autofill addresses: DISABLED
   6.3 Payment methods: DISABLED
STANDARD_EOF

chown ga:ga /home/ga/Desktop/browser_config_standard.txt
echo "Created ~/Desktop/browser_config_standard.txt"

# ============================================================
# Record baseline state for verification
# ============================================================
echo "Recording baseline state..."
python3 -c "
import json

baseline = {
    'initial_bookmarks_flat': True,
    'initial_bookmark_count': 24,
    'initial_folders': [],
    'initial_homepage': 'https://www.google.com/',
    'initial_search_engines': [],
    'initial_download_dir': '/home/ga/Downloads',
    'initial_password_saving': True,
    'initial_autofill': True,
    'initial_third_party_cookies_blocked': False,
    'initial_dnt': False,
    'initial_safe_browsing_enhanced': False,
    'expected_folders': ['Federal Agencies', 'Standards Bodies', 'International', 'Legislative Resources', 'Consumer Protection'],
    'expected_subfolders_federal': ['FDA', 'EPA', 'OSHA', 'SEC'],
    'expected_search_keywords': ['cfr', 'fr', 'edgar'],
    'expected_homepage': 'https://www.federalregister.gov',
    'expected_startup_urls': ['https://www.federalregister.gov', 'https://www.regulations.gov', 'https://www.ecfr.gov'],
    'expected_download_dir': '/home/ga/Documents/Regulatory_Downloads',
    'task_id': 'compliance_research_workspace@1'
}

with open('/tmp/compliance_research_workspace_baseline.json', 'w') as f:
    json.dump(baseline, f, indent=2)

print('Baseline recorded successfully')
"

# ============================================================
# Create the regulatory downloads directory
# ============================================================
mkdir -p /home/ga/Documents/Regulatory_Downloads
chown -R ga:ga /home/ga/Documents/Regulatory_Downloads
echo "Created /home/ga/Documents/Regulatory_Downloads"

# ============================================================
# Start Chrome and navigate to about:blank
# ============================================================
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Final focus
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "Chrome CDP is accessible"
else
    echo "Warning: Chrome CDP not responding"
fi

# Take a screenshot of initial state
if command -v import &> /dev/null; then
    su - ga -c "DISPLAY=:1 import -window root /tmp/initial_screenshot.png" 2>/dev/null || true
    echo "Initial screenshot saved"
fi

echo "=== Setup complete ==="
echo ""
echo "Chrome is ready with 24 flat regulatory bookmarks on the bookmark bar."
echo "Non-compliant settings are active (wrong homepage, no search engines, etc.)."
echo ""
echo "The Browser Configuration Standard is at: ~/Desktop/browser_config_standard.txt"
echo ""
echo "Agent must read the standard and implement ALL requirements:"
echo "  1. Organize 24 bookmarks into 5 folders with sub-folders"
echo "  2. Add 3 custom search engine shortcuts (cfr, fr, edgar)"
echo "  3. Set homepage to federalregister.gov and configure startup pages"
echo "  4. Configure privacy settings (block cookies, DNT, safe browsing)"
echo "  5. Set download directory to Regulatory_Downloads"
echo "  6. Disable password saving, autofill, and payment methods"
