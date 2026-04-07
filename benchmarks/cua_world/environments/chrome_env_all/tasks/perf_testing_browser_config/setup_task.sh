#!/bin/bash
set -euo pipefail

echo "=== Setting up Performance Testing Browser Config task ==="

export DISPLAY=${DISPLAY:-:1}

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Prepare directories
echo "Creating required directories..."
mkdir -p /home/ga/projects/test-artifacts
chown -R ga:ga /home/ga/projects

mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Desktop

# 2. Write the specification file
echo "Writing specification document..."
cat > /home/ga/Desktop/perf_testing_standard.txt << 'EOF'
ENGINEERING TEAM: PERFORMANCE TESTING BROWSER STANDARD v1.0
===========================================================
All frontend developers must configure their local testing browser to match these specifications to ensure consistent performance profiling.

SECTION 1: EXPERIMENTAL FLAGS (chrome://flags)
----------------------------------------------
Enable the following:
- Experimental Web Platform features
- Parallel downloading
- Experimental QUIC protocol

Disable the following:
- Smooth Scrolling (interferes with scroll jank profiling)
- Auto Dark Mode for Web Contents

SECTION 2: SEARCH ENGINE SHORTCUTS
----------------------------------
Add these custom search engines for quick documentation access:
- Keyword: mdn -> URL: https://developer.mozilla.org/en-US/search?q=%s
- Keyword: npm -> URL: https://www.npmjs.com/search?q=%s
- Keyword: gh  -> URL: https://github.com/search?q=%s
- Keyword: can -> URL: https://caniuse.com/?search=%s

SECTION 3: HOMEPAGE & STARTUP
-----------------------------
- Homepage: https://github.com/dashboard
- On startup: Open specific pages
  1. https://github.com/dashboard
  2. https://developer.chrome.com/
  3. https://web.dev/

SECTION 4: FONT RENDERING
-------------------------
For accessibility layout testing, adjust font sizes in Appearance settings:
- Default font size: 18 (Medium/Custom)
- Fixed-width font size: 15
- Minimum font size: 12

SECTION 5: DOWNLOADS
--------------------
- Location: /home/ga/projects/test-artifacts
- Ask where to save each file before downloading: ENABLED

SECTION 6: PRIVACY & CREDENTIALS
--------------------------------
- Block third-party cookies
- Send a "Do Not Track" request with your browsing traffic: ENABLED
- Safe Browsing: No protection (turn off completely for local testing)
- Password Manager: Disable "Offer to save passwords"
- Autofill: Disable saving addresses and payment methods
EOF
chown ga:ga /home/ga/Desktop/perf_testing_standard.txt

# 3. Stop any existing Chrome instances to ensure clean state
echo "Stopping existing Chrome instances..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2

# 4. Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh > /tmp/chrome_launch.log 2>&1 &"
sleep 5

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome"; then
        echo "Chrome window detected"
        break
    fi
    sleep 1
done

# Maximize Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Chromium" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus window
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="