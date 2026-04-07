#!/bin/bash
set -e
echo "=== Setting up create_custom_stylesheet task ==="

# Source utility functions if available, otherwise define basics
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    TIDDLER_DIR="/home/ga/mywiki/tiddlers"
    take_screenshot() {
        DISPLAY=:1 import -window root "$1" 2>/dev/null || DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state (remove any existing stylesheet tiddlers that might cheat the task)
find "$TIDDLER_DIR" -type f -name "*.tid" -exec grep -l "\$:/tags/Stylesheet" {} \; 2>/dev/null | xargs -r rm -f
rm -f "$TIDDLER_DIR/Custom Dark Theme.tid" "$TIDDLER_DIR/Custom_Dark_Theme.tid" 2>/dev/null || true
curl -s -X DELETE "http://localhost:8080/bags/default/tiddlers/Custom%20Dark%20Theme" >/dev/null 2>&1 || true

# 3. Seed realistic documentation tiddlers so the theme changes are obvious
cat > "$TIDDLER_DIR/Getting_Started_with_REST_APIs.tid" << 'EOF'
created: 20240115120000000
modified: 20240115120000000
tags: Documentation
title: Getting Started with REST APIs

! Introduction to REST APIs

REST (Representational State Transfer) is an architectural style for designing networked applications. It relies on a stateless, client-server communication protocol.

!! Common HTTP Methods

|!Method |!Purpose |!Idempotent |
|GET |Retrieve a resource |Yes |
|POST |Create a new resource |No |
|PUT |Update/replace a resource |Yes |
|DELETE |Remove a resource |Yes |
EOF

cat > "$TIDDLER_DIR/HTTP_Status_Codes_Reference.tid" << 'EOF'
created: 20240116090000000
modified: 20240116090000000
tags: Documentation Reference
title: HTTP Status Codes Reference

! HTTP Status Codes

!! 2xx Success
* 200 OK
* 201 Created
* 204 No Content

!! 4xx Client Errors
* 400 Bad Request
* 401 Unauthorized
* 403 Forbidden
* 404 Not Found
EOF

cat > "$TIDDLER_DIR/Design_System_Color_Tokens.tid" << 'EOF'
created: 20240121080000000
modified: 20240122090000000
tags: Documentation Design
title: Design System Color Tokens

! Design System Color Tokens

Color tokens provide a semantic layer between raw color values and their usage in UI components.

!! Core Palette (Catppuccin Mocha)

|!Token |!Hex |!Usage |
|Base |`#1e1e2e` |Page background |
|Mantle |`#181825` |Sidebar, secondary surfaces |
|Text |`#cdd6f4` |Primary text |
|Lavender |`#cba6f7` |Accents, headings |
|Blue |`#89b4fa` |Links, interactive elements |
EOF

chown -R ga:ga "$TIDDLER_DIR"

# 4. Restart TiddlyWiki to ensure it picks up changes cleanly
pkill -f tiddlywiki || true
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# 5. Handle Firefox
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Focus, maximize, and refresh Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    sleep 1
    # Refresh to ensure latest tiddlers are loaded
    DISPLAY=:1 xdotool key F5
    sleep 3
fi

# Open one of the documentation tiddlers to ensure UI is visible
DISPLAY=:1 xdotool key ctrl+f
sleep 0.5
DISPLAY=:1 xdotool type "Getting Started"
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 1
DISPLAY=:1 xdotool key Escape

# 6. Take initial screenshot
sleep 1
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="