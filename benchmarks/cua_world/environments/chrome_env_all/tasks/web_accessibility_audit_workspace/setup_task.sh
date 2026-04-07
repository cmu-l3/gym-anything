#!/bin/bash
set -euo pipefail

echo "=== Setting up Web Accessibility Audit Workspace ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure target download directory exists
mkdir -p /home/ga/Documents/WCAG_Audits
chown -R ga:ga /home/ga/Documents/WCAG_Audits

# Stop Chrome to safely modify profile
echo "Stopping Chrome..."
pkill -f "chrome" 2>/dev/null || true
sleep 2
pkill -9 -f "chrome" 2>/dev/null || true

# Setup Chrome Profile
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome

# Create Bookmarks JSON with 22 flat bookmarks
echo "Generating Bookmarks..."
python3 << 'PYEOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

bookmarks_list = [
    ("W3C WCAG 2.1", "https://www.w3.org/WAI/standards-guidelines/wcag/"),
    ("Section 508", "https://www.section508.gov/"),
    ("ADA.gov", "https://www.ada.gov/"),
    ("WebAIM Checklist", "https://webaim.org/standards/wcag/checklist"),
    ("WAVE Tool", "https://wave.webaim.org/"),
    ("aXe Deque", "https://www.deque.com/axe/"),
    ("Lighthouse", "https://developers.google.com/web/tools/lighthouse"),
    ("Accessibility Insights", "https://accessibilityinsights.io/"),
    ("Color Contrast Analyzer", "https://developer.paciellogroup.com/resources/contrastanalyser/"),
    ("NVDA Screen Reader", "https://www.nvaccess.org/"),
    ("JAWS", "https://www.freedomscientific.com/products/software/jaws/"),
    ("VoiceOver", "https://www.apple.com/accessibility/vision/"),
    ("TalkBack", "https://support.google.com/accessibility/android/"),
    ("WAI-ARIA Practices", "https://www.w3.org/WAI/ARIA/apg/"),
    ("MDN ARIA", "https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA"),
    ("Inclusive Components", "https://inclusive-components.design/"),
    ("A11y Project", "https://www.a11yproject.com/"),
    ("YouTube", "https://www.youtube.com/"),
    ("Netflix", "https://www.netflix.com/"),
    ("Reddit", "https://www.reddit.com/"),
    ("Twitter", "https://twitter.com/"),
    ("Spotify", "https://open.spotify.com/")
]

children = []
bid = 5

for i, (name, url) in enumerate(bookmarks_list):
    ts = str(chrome_base - (i + 1) * 600000000)
    children.append({
        "date_added": ts,
        "guid": str(uuid.uuid4()),
        "id": str(bid),
        "name": name,
        "type": "url",
        "url": url
    })
    bid += 1

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {
            "children": children,
            "date_added": str(chrome_base),
            "date_modified": str(chrome_base),
            "id": "1",
            "name": "Bookmarks bar",
            "type": "folder"
        },
        "other": {"children": [], "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

profile_dir = "/home/ga/.config/google-chrome/Default"
os.makedirs(profile_dir, exist_ok=True)
with open(os.path.join(profile_dir, "Bookmarks"), "w") as f:
    json.dump(bookmarks, f, indent=3)
PYEOF
chown ga:ga "$CHROME_PROFILE/Bookmarks"

# Ensure basic Preferences structure exists so agent isn't fighting a corrupt profile
cat > "$CHROME_PROFILE/Preferences" << 'PREFEOF'
{
  "browser": {"has_seen_welcome_page": true},
  "profile": {"password_manager_enabled": false}
}
PREFEOF
chown ga:ga "$CHROME_PROFILE/Preferences"

# Start Chrome
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable --no-first-run --no-default-browser-check &"
sleep 5

# Maximize Chrome window
DISPLAY=:1 wmctrl -r "Google Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Google Chrome" 2>/dev/null || true

# Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="