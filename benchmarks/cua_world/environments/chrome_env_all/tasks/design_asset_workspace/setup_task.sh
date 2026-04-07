#!/bin/bash
set -euo pipefail

echo "=== Setting up Design Asset Workspace Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/projects/design-assets
mkdir -p /tmp/design_assets_server

# Set proper ownership
chown -R ga:ga /home/ga/projects

# =====================================================================
# 1. Create the Design Standard Specification Document
# =====================================================================
cat > /home/ga/Desktop/design_workspace_standard.txt << 'EOF'
AGENCY DESIGN TEAM BROWSER STANDARD v1.0

To ensure consistent color rendering, precise layout inspection, and synchronized asset access across our design team, please configure your Chrome browser exactly as specified below:

1. Chrome Flags (chrome://flags)
   - Experimental Web Platform features: ENABLED (Required for CSS subgrid/container queries)
   - GPU rasterization: ENABLED (Required for hardware-accelerated Figma rendering)
   - Smooth Scrolling: DISABLED (Required for pixel-precise scroll positioning)
   - Experimental QUIC protocol: DISABLED (Required for predictable network debugging)

2. Asset Downloads
   Download our core design system files from our internal server (http://localhost:8080) and save them to your local directory: ~/projects/design-assets/
   - brand_color_palette.json
   - icon_sprite_sheet.svg
   - typography_guide.pdf

3. Custom Search Engines
   Add these search engine shortcuts (Settings > Search engine > Manage search engines):
   - Dribbble | Keyword: dribbble | URL: https://dribbble.com/search/%s
   - Google Fonts | Keyword: gfonts | URL: https://fonts.google.com/?query=%s
   - Material Icons | Keyword: icons | URL: https://fonts.google.com/icons?icon.query=%s

4. Bookmark Organization
   Your bookmark bar currently has 20 loose bookmarks. Organize them into exactly TWO folders:
   - "Design Tools" (Figma, Adobe Color, Canva, Sketch, InVision, Zeplin, Abstract, Principle, Framer, Webflow, Spline, Rive)
   - "Inspiration" (Dribbble, Behance, Awwwards, SiteInspire, Muzli, Designspiration, Pinterest, Unsplash)
   * Do not leave any loose bookmarks directly on the bookmark bar.

5. Browser Settings
   - Homepage: https://www.figma.com
   - On Startup: Continue where you left off
   - Download Location: /home/ga/projects/design-assets/
   - Ask where to save each file before downloading: ENABLED
   - Offer to save passwords: DISABLED
EOF

# =====================================================================
# 2. Generate Assets and Start Local HTTP Server
# =====================================================================
cat > /tmp/design_assets_server/brand_color_palette.json << 'EOF'
{
  "system": "Material Design 3",
  "colors": {
    "primary": "#6750A4",
    "onPrimary": "#FFFFFF",
    "primaryContainer": "#EADDFF",
    "secondary": "#625B71",
    "secondaryContainer": "#E8DEF8",
    "tertiary": "#7D5260",
    "background": "#FFFBFE",
    "surface": "#FFFBFE",
    "error": "#B3261E"
  }
}
EOF

cat > /tmp/design_assets_server/icon_sprite_sheet.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" style="display: none;">
  <symbol id="icon-home" viewBox="0 0 24 24">
    <path d="M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z"/>
  </symbol>
  <symbol id="icon-search" viewBox="0 0 24 24">
    <path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>
  </symbol>
  <symbol id="icon-settings" viewBox="0 0 24 24">
    <path d="M19.14,12.94c0.04-0.3,0.06-0.61,0.06-0.94c0-0.32-0.02-0.64-0.06-0.94l2.03-1.58c0.18-0.14,0.23-0.41,0.12-0.61 l-1.92-3.32c-0.12-0.22-0.37-0.29-0.59-0.22l-2.39,0.96c-0.5-0.38-1.03-0.7-1.62-0.94L14.4,2.81c-0.04-0.24-0.24-0.41-0.48-0.41 h-3.84c-0.24,0-0.43,0.17-0.47,0.41L9.25,5.35C8.66,5.59,8.12,5.92,7.63,6.29L5.24,5.33c-0.22-0.08-0.47,0-0.59,0.22L2.73,8.87 C2.62,9.08,2.66,9.34,2.86,9.48l2.03,1.58C4.84,11.36,4.8,11.69,4.8,12s0.02,0.64,0.06,0.94l-2.03,1.58 c-0.18,0.14-0.23,0.41-0.12,0.61l1.92,3.32c0.12,0.22,0.37,0.29,0.59,0.22l2.39-0.96c0.5,0.38,1.03,0.7,1.62,0.94l0.36,2.54 c0.05,0.24,0.24,0.41,0.48,0.41h3.84c0.24,0,0.43-0.17,0.47-0.41l0.36-2.54c0.59-0.24,1.13-0.56,1.62-0.94l2.39,0.96 c0.22,0.08,0.47,0,0.59-0.22l1.92-3.32c0.12-0.22,0.07-0.49-0.12-0.61L19.14,12.94z M12,15.6c-1.98,0-3.6-1.62-3.6-3.6 s1.62-3.6,3.6-3.6s3.6,1.62,3.6,3.6S13.98,15.6,12,15.6z"/>
  </symbol>
</svg>
EOF

cat > /tmp/design_assets_server/typography_guide.pdf << 'EOF'
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 53 >>
stream
BT
/F1 24 Tf
100 700 Td
(Agency Typography System: Inter) Tj
ET
endstream
endobj
trailer
<< /Root 1 0 R /Size 5 >>
%%EOF
EOF

# Kill any existing Python HTTP servers and start ours
pkill -f "http.server 8080" 2>/dev/null || true
cd /tmp/design_assets_server
su - ga -c "python3 -m http.server 8080 --directory /tmp/design_assets_server > /dev/null 2>&1 &"

# =====================================================================
# 3. Setup Chrome Profile with Flat Bookmarks
# =====================================================================
echo "Stopping Chrome to inject test data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# Generate flat bookmarks JSON via Python for robust formatting
python3 << 'PYEOF'
import json, uuid, time

chrome_base = (int(time.time()) + 11644473600) * 1000000

design_tools = [
    ("Figma", "https://figma.com/"), ("Adobe Color", "https://color.adobe.com/"), 
    ("Canva", "https://canva.com/"), ("Sketch", "https://sketch.com/"), 
    ("InVision", "https://invisionapp.com/"), ("Zeplin", "https://zeplin.io/"), 
    ("Abstract", "https://abstract.com/"), ("Principle", "https://principleformac.com/"), 
    ("Framer", "https://framer.com/"), ("Webflow", "https://webflow.com/"), 
    ("Spline", "https://spline.design/"), ("Rive", "https://rive.app/")
]

inspiration = [
    ("Dribbble", "https://dribbble.com/"), ("Behance", "https://behance.net/"), 
    ("Awwwards", "https://awwwards.com/"), ("SiteInspire", "https://siteinspire.com/"), 
    ("Muzli", "https://muz.li/"), ("Designspiration", "https://designspiration.com/"), 
    ("Pinterest", "https://pinterest.com/"), ("Unsplash", "https://unsplash.com/")
]

# Mix them together to ensure they are flat
all_bms = design_tools + inspiration
children = []
bid = 10

for i, (name, url) in enumerate(all_bms):
    children.append({
        "date_added": str(chrome_base - (i * 10000000)),
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

with open('/home/ga/.config/google-chrome/Default/Bookmarks', 'w') as f:
    json.dump(bookmarks, f, indent=3)
PYEOF

chown ga:ga "$CHROME_PROFILE/Bookmarks"

# =====================================================================
# 4. Launch Chrome
# =====================================================================
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh http://localhost:8080 > /tmp/chrome_launch.log 2>&1 &"

# Wait for Chrome window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome\|Chromium"; then
        break
    fi
    sleep 1
done

# Maximize Chrome
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="