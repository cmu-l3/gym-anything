#!/usr/bin/env bash
# set -euo pipefail

echo "=== Developer Workflow Audit Task Setup ==="
echo "Task: Configure browser per team development workflow standard"

# Wait for environment to be ready
sleep 2

# Stop Chrome if running to modify bookmarks and preferences safely
echo "Stopping Chrome to prepare profile..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 3

# Ensure Chrome profile directory exists
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga "/home/ga/.config/google-chrome"

# ============================================================
# CREATE BOOKMARKS - 40 bookmarks scattered FLAT on bookmark bar
# ============================================================
echo "Creating initial bookmarks (40 flat bookmarks - mixed dev and personal)..."
cat > "$CHROME_PROFILE/Bookmarks" << 'BOOKMARKS_EOF'
{
   "checksum": "developer_workflow_audit_initial",
   "roots": {
      "bookmark_bar": {
         "children": [
            {
               "date_added": "13360799510000000",
               "guid": "a0000000-0000-4000-a000-000000000001",
               "id": "5",
               "name": "GitHub",
               "type": "url",
               "url": "https://github.com/"
            },
            {
               "date_added": "13360799510100000",
               "guid": "a0000000-0000-4000-a000-000000000002",
               "id": "6",
               "name": "YouTube",
               "type": "url",
               "url": "https://www.youtube.com/"
            },
            {
               "date_added": "13360799510200000",
               "guid": "a0000000-0000-4000-a000-000000000003",
               "id": "7",
               "name": "Stack Overflow",
               "type": "url",
               "url": "https://stackoverflow.com/"
            },
            {
               "date_added": "13360799510300000",
               "guid": "a0000000-0000-4000-a000-000000000004",
               "id": "8",
               "name": "Netflix",
               "type": "url",
               "url": "https://www.netflix.com/"
            },
            {
               "date_added": "13360799510400000",
               "guid": "a0000000-0000-4000-a000-000000000005",
               "id": "9",
               "name": "GitHub Pull Requests",
               "type": "url",
               "url": "https://github.com/pulls"
            },
            {
               "date_added": "13360799510500000",
               "guid": "a0000000-0000-4000-a000-000000000006",
               "id": "10",
               "name": "Reddit",
               "type": "url",
               "url": "https://www.reddit.com/"
            },
            {
               "date_added": "13360799510600000",
               "guid": "a0000000-0000-4000-a000-000000000007",
               "id": "11",
               "name": "Python Docs",
               "type": "url",
               "url": "https://docs.python.org/"
            },
            {
               "date_added": "13360799510700000",
               "guid": "a0000000-0000-4000-a000-000000000008",
               "id": "12",
               "name": "Spotify",
               "type": "url",
               "url": "https://www.spotify.com/"
            },
            {
               "date_added": "13360799510800000",
               "guid": "a0000000-0000-4000-a000-000000000009",
               "id": "13",
               "name": "MDN Web Docs",
               "type": "url",
               "url": "https://developer.mozilla.org/"
            },
            {
               "date_added": "13360799510900000",
               "guid": "a0000000-0000-4000-a000-000000000010",
               "id": "14",
               "name": "Twitter",
               "type": "url",
               "url": "https://twitter.com/"
            },
            {
               "date_added": "13360799511000000",
               "guid": "a0000000-0000-4000-a000-000000000011",
               "id": "15",
               "name": "Docker Hub",
               "type": "url",
               "url": "https://hub.docker.com/"
            },
            {
               "date_added": "13360799511100000",
               "guid": "a0000000-0000-4000-a000-000000000012",
               "id": "16",
               "name": "Instagram",
               "type": "url",
               "url": "https://www.instagram.com/"
            },
            {
               "date_added": "13360799511200000",
               "guid": "a0000000-0000-4000-a000-000000000013",
               "id": "17",
               "name": "Kubernetes Docs",
               "type": "url",
               "url": "https://kubernetes.io/docs/"
            },
            {
               "date_added": "13360799511300000",
               "guid": "a0000000-0000-4000-a000-000000000014",
               "id": "18",
               "name": "Amazon",
               "type": "url",
               "url": "https://www.amazon.com/"
            },
            {
               "date_added": "13360799511400000",
               "guid": "a0000000-0000-4000-a000-000000000015",
               "id": "19",
               "name": "Terraform Registry",
               "type": "url",
               "url": "https://registry.terraform.io/"
            },
            {
               "date_added": "13360799511500000",
               "guid": "a0000000-0000-4000-a000-000000000016",
               "id": "20",
               "name": "eBay",
               "type": "url",
               "url": "https://www.ebay.com/"
            },
            {
               "date_added": "13360799511600000",
               "guid": "a0000000-0000-4000-a000-000000000017",
               "id": "21",
               "name": "Grafana",
               "type": "url",
               "url": "https://grafana.com/"
            },
            {
               "date_added": "13360799511700000",
               "guid": "a0000000-0000-4000-a000-000000000018",
               "id": "22",
               "name": "Yelp",
               "type": "url",
               "url": "https://www.yelp.com/"
            },
            {
               "date_added": "13360799511800000",
               "guid": "a0000000-0000-4000-a000-000000000019",
               "id": "23",
               "name": "Prometheus",
               "type": "url",
               "url": "https://prometheus.io/"
            },
            {
               "date_added": "13360799511900000",
               "guid": "a0000000-0000-4000-a000-000000000020",
               "id": "24",
               "name": "TripAdvisor",
               "type": "url",
               "url": "https://www.tripadvisor.com/"
            },
            {
               "date_added": "13360799512000000",
               "guid": "a0000000-0000-4000-a000-000000000021",
               "id": "25",
               "name": "Jenkins",
               "type": "url",
               "url": "https://www.jenkins.io/"
            },
            {
               "date_added": "13360799512100000",
               "guid": "a0000000-0000-4000-a000-000000000022",
               "id": "26",
               "name": "ESPN",
               "type": "url",
               "url": "https://www.espn.com/"
            },
            {
               "date_added": "13360799512200000",
               "guid": "a0000000-0000-4000-a000-000000000023",
               "id": "27",
               "name": "Jira",
               "type": "url",
               "url": "https://jira.atlassian.com/"
            },
            {
               "date_added": "13360799512300000",
               "guid": "a0000000-0000-4000-a000-000000000024",
               "id": "28",
               "name": "Weather.com",
               "type": "url",
               "url": "https://weather.com/"
            },
            {
               "date_added": "13360799512400000",
               "guid": "a0000000-0000-4000-a000-000000000025",
               "id": "29",
               "name": "Confluence",
               "type": "url",
               "url": "https://confluence.atlassian.com/"
            },
            {
               "date_added": "13360799512500000",
               "guid": "a0000000-0000-4000-a000-000000000026",
               "id": "30",
               "name": "Craigslist",
               "type": "url",
               "url": "https://www.craigslist.org/"
            },
            {
               "date_added": "13360799512600000",
               "guid": "a0000000-0000-4000-a000-000000000027",
               "id": "31",
               "name": "npm",
               "type": "url",
               "url": "https://www.npmjs.com/"
            },
            {
               "date_added": "13360799512700000",
               "guid": "a0000000-0000-4000-a000-000000000028",
               "id": "32",
               "name": "Pinterest",
               "type": "url",
               "url": "https://www.pinterest.com/"
            },
            {
               "date_added": "13360799512800000",
               "guid": "a0000000-0000-4000-a000-000000000029",
               "id": "33",
               "name": "PyPI",
               "type": "url",
               "url": "https://pypi.org/"
            },
            {
               "date_added": "13360799512900000",
               "guid": "a0000000-0000-4000-a000-000000000030",
               "id": "34",
               "name": "Tumblr",
               "type": "url",
               "url": "https://www.tumblr.com/"
            },
            {
               "date_added": "13360799513000000",
               "guid": "a0000000-0000-4000-a000-000000000031",
               "id": "35",
               "name": "Go Packages",
               "type": "url",
               "url": "https://pkg.go.dev/"
            },
            {
               "date_added": "13360799513100000",
               "guid": "a0000000-0000-4000-a000-000000000032",
               "id": "36",
               "name": "Twitch",
               "type": "url",
               "url": "https://www.twitch.tv/"
            },
            {
               "date_added": "13360799513200000",
               "guid": "a0000000-0000-4000-a000-000000000033",
               "id": "37",
               "name": "crates.io",
               "type": "url",
               "url": "https://crates.io/"
            },
            {
               "date_added": "13360799513300000",
               "guid": "a0000000-0000-4000-a000-000000000034",
               "id": "38",
               "name": "Reddit Programming",
               "type": "url",
               "url": "https://www.reddit.com/r/programming/"
            },
            {
               "date_added": "13360799513400000",
               "guid": "a0000000-0000-4000-a000-000000000035",
               "id": "39",
               "name": "AWS Docs",
               "type": "url",
               "url": "https://docs.aws.amazon.com/"
            },
            {
               "date_added": "13360799513500000",
               "guid": "a0000000-0000-4000-a000-000000000036",
               "id": "40",
               "name": "Reddit Gaming",
               "type": "url",
               "url": "https://www.reddit.com/r/gaming/"
            },
            {
               "date_added": "13360799513600000",
               "guid": "a0000000-0000-4000-a000-000000000037",
               "id": "41",
               "name": "GitHub Notifications",
               "type": "url",
               "url": "https://github.com/notifications"
            },
            {
               "date_added": "13360799513700000",
               "guid": "a0000000-0000-4000-a000-000000000038",
               "id": "42",
               "name": "Stack Overflow - Python",
               "type": "url",
               "url": "https://stackoverflow.com/questions/tagged/python"
            },
            {
               "date_added": "13360799513800000",
               "guid": "a0000000-0000-4000-a000-000000000039",
               "id": "43",
               "name": "Python Standard Library",
               "type": "url",
               "url": "https://docs.python.org/3/library/"
            },
            {
               "date_added": "13360799513900000",
               "guid": "a0000000-0000-4000-a000-000000000040",
               "id": "44",
               "name": "MDN Web API",
               "type": "url",
               "url": "https://developer.mozilla.org/en-US/docs/Web/API"
            }
         ],
         "date_added": "13360799500000000",
         "date_modified": "13360799513900000",
         "guid": "00000000-0000-4000-a000-000000000000",
         "id": "1",
         "name": "Bookmarks bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000001",
         "id": "2",
         "name": "Other bookmarks",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13360799500000000",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000002",
         "id": "3",
         "name": "Mobile bookmarks",
         "type": "folder"
      }
   },
   "version": 1
}
BOOKMARKS_EOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"
echo "Created bookmarks file with 40 flat bookmarks (22 dev + 18 personal)"

# ============================================================
# CREATE PREFERENCES - Non-compliant defaults
# ============================================================
echo "Creating non-compliant Chrome Preferences..."
cat > "$CHROME_PROFILE/Preferences" << 'PREFS_EOF'
{
   "bookmark_bar": {
      "show_on_all_tabs": true
   },
   "browser": {
      "show_home_button": true,
      "check_default_browser": false
   },
   "download": {
      "default_directory": "/home/ga/Downloads",
      "prompt_for_download": false
   },
   "homepage": "https://www.google.com/",
   "homepage_is_newtabpage": false,
   "session": {
      "restore_on_startup": 5
   },
   "profile": {
      "default_content_setting_values": {
         "cookies": 1
      },
      "cookie_controls_mode": 0,
      "name": "Developer"
   },
   "enable_do_not_track": false,
   "webkit": {
      "webprefs": {
         "default_font_size": 16,
         "default_fixed_font_size": 13
      }
   },
   "devtools": {
      "preferences": {}
   }
}
PREFS_EOF

chown ga:ga "$CHROME_PROFILE/Preferences"
echo "Created Preferences with non-compliant settings:"
echo "  - Homepage: google.com (should be github.com)"
echo "  - No custom search engines configured"
echo "  - Third-party cookies allowed (should be blocked)"
echo "  - DNT disabled (should be enabled)"
echo "  - Download dir: /home/ga/Downloads (should be /home/ga/projects/downloads)"
echo "  - prompt_for_download: false (should be true)"
echo "  - restore_on_startup: 5 (should be 1)"

# ============================================================
# CREATE THE TEAM STANDARD DOCUMENT
# ============================================================
echo "Creating team browser standard document..."
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/dev_team_browser_standard.txt << 'STANDARD_EOF'
ENGINEERING TEAM BROWSER CONFIGURATION STANDARD
Version: 3.0
Last Updated: 2026-02-15
Team: Platform Engineering

== SECTION 1: BOOKMARK ORGANIZATION ==

All bookmarks must be organized into the following structure on the Bookmark Bar:

1.1 "Development" folder:
    - Sub-folder "Source Control" - All GitHub bookmarks
    - Sub-folder "Documentation" - All documentation sites (docs.python.org, developer.mozilla.org, kubernetes.io/docs, docs.aws.amazon.com)
    - Sub-folder "Package Registries" - All package registry sites (npmjs.com, pypi.org, pkg.go.dev, crates.io, hub.docker.com, registry.terraform.io)
    - Sub-folder "DevOps" - CI/CD and monitoring tools (grafana.com, prometheus.io, jenkins.io)
    - Sub-folder "Project Management" - Jira and Confluence bookmarks

1.2 "Reference" folder:
    - Stack Overflow bookmarks
    - Other Q&A / reference sites

1.3 "Personal" folder:
    - ALL personal/non-work bookmarks must be moved here
    - This includes social media, entertainment, shopping, news, etc.

== SECTION 2: SEARCH ENGINE SHORTCUTS ==

Configure these custom search engines:

2.1 Keyword: "gh" - URL: https://github.com/search?q=%s&type=repositories
    Name: "GitHub Repository Search"

2.2 Keyword: "so" - URL: https://stackoverflow.com/search?q=%s
    Name: "Stack Overflow Search"

2.3 Keyword: "mdn" - URL: https://developer.mozilla.org/en-US/search?q=%s
    Name: "MDN Web Docs Search"

2.4 Keyword: "pypi" - URL: https://pypi.org/search/?q=%s
    Name: "PyPI Package Search"

== SECTION 3: HOMEPAGE AND STARTUP ==

3.1 Homepage: https://github.com
3.2 On startup, restore the previous session (do NOT open specific pages)

== SECTION 4: COOKIE AND PRIVACY POLICY ==

4.1 Block third-party cookies
4.2 Clear cookies and site data when all windows are closed: DISABLED
    (We need persistent sessions for dev tools)
4.3 Send "Do Not Track" requests: ENABLED

== SECTION 5: DOWNLOAD CONFIGURATION ==

5.1 Default download directory: /home/ga/projects/downloads
5.2 Always ask where to save: ENABLED

== SECTION 6: DEVELOPER TOOLS ==

6.1 Ensure DevTools opens undocked (in a separate window) - this is a preference
STANDARD_EOF

chown ga:ga /home/ga/Desktop/dev_team_browser_standard.txt
echo "Created team standard at ~/Desktop/dev_team_browser_standard.txt"

# ============================================================
# CREATE DOWNLOAD DIRECTORY
# ============================================================
echo "Creating project downloads directory..."
mkdir -p /home/ga/projects/downloads
chown -R ga:ga /home/ga/projects
echo "Created /home/ga/projects/downloads"

# ============================================================
# RECORD BASELINE
# ============================================================
echo "Recording baseline state..."
cat > /tmp/developer_workflow_audit_baseline.json << 'BASELINE_EOF'
{
    "task": "developer_workflow_audit",
    "initial_state": {
        "total_bookmarks": 40,
        "dev_bookmarks": 22,
        "personal_bookmarks": 18,
        "bookmark_folders": 0,
        "custom_search_engines": 0,
        "homepage": "https://www.google.com/",
        "restore_on_startup": 5,
        "cookie_controls_mode": 0,
        "enable_do_not_track": false,
        "download_directory": "/home/ga/Downloads",
        "prompt_for_download": false
    },
    "expected_state": {
        "bookmark_folders": ["Development", "Reference", "Personal"],
        "dev_subfolders": ["Source Control", "Documentation", "Package Registries", "DevOps", "Project Management"],
        "custom_search_engines": ["gh", "so", "mdn", "pypi"],
        "homepage": "https://github.com",
        "restore_on_startup": 1,
        "cookie_controls_mode": 1,
        "enable_do_not_track": true,
        "download_directory": "/home/ga/projects/downloads",
        "prompt_for_download": true
    }
}
BASELINE_EOF

echo "Baseline recorded to /tmp/developer_workflow_audit_baseline.json"

# ============================================================
# LAUNCH CHROME
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
echo "Developer Workflow Audit Task"
echo "============================="
echo "Chrome is running with 40 scattered bookmarks and default settings."
echo "The team browser standard is at: ~/Desktop/dev_team_browser_standard.txt"
echo ""
echo "Agent must:"
echo "  1. Read the standard document"
echo "  2. Organize 40 bookmarks into Development/Reference/Personal folders"
echo "  3. Create sub-folders within Development (Source Control, Documentation, etc.)"
echo "  4. Add 4 custom search engine shortcuts (gh, so, mdn, pypi)"
echo "  5. Set homepage to github.com"
echo "  6. Set startup to restore previous session"
echo "  7. Block third-party cookies and enable DNT"
echo "  8. Change download directory to /home/ga/projects/downloads"
echo "  9. Enable prompt_for_download"
