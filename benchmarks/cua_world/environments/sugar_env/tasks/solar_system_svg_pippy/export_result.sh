#!/bin/bash
echo "=== Exporting solar_system_svg_pippy task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/solar_task_end.png" 2>/dev/null || true

SVG_FILE="/home/ga/Documents/solar_system.svg"
TASK_START=$(cat /tmp/solar_system_start_ts 2>/dev/null || echo "0")

FILE_MODIFIED="false"
FILE_MTIME=0

if [ -f "$SVG_FILE" ]; then
    FILE_MTIME=$(stat --format=%Y "$SVG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Run python script to analyze SVG
python3 << 'PYEOF' > /tmp/solar_svg_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/solar_svg_analysis.json
import json
import re
import os

result = {
    "file_exists": False,
    "has_svg_tag": False,
    "circle_count": 0,
    "colors": [],
    "labels_found": {},
    "file_size": 0,
    "sun_found": False,
    "error": None
}

svg_path = "/home/ga/Documents/solar_system.svg"
if os.path.exists(svg_path):
    result["file_exists"] = True
    result["file_size"] = os.path.getsize(svg_path)
    try:
        with open(svg_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
            
        result["has_svg_tag"] = bool(re.search(r'<svg\b', content, re.IGNORECASE))
        
        # count circles and ellipses
        circles = re.findall(r'<(?:circle|ellipse)\b([^>]*)>', content, re.IGNORECASE)
        result["circle_count"] = len(circles)
        
        # extract fills
        colors = []
        for attrs in circles:
            m = re.search(r'fill\s*=\s*["\']([^"\']+)["\']', attrs, re.IGNORECASE)
            if m:
                colors.append(m.group(1).lower().strip())
        result["colors"] = list(set(colors))
        
        # Check for Sun (warm color)
        warm_colors = ['yellow', 'orange', 'gold', '#ffd700', '#ffa500', '#ffff00', 'red']
        sun_color_found = any(any(w in c for w in warm_colors) for c in colors)
        result["sun_found"] = sun_color_found
        
        # Check planet names
        planets = ["Mercury", "Venus", "Earth", "Mars", "Jupiter", "Saturn", "Uranus", "Neptune"]
        for p in planets:
            result["labels_found"][p] = bool(re.search(r'\b' + p + r'\b', content, re.IGNORECASE))
            
    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Check Sugar Journal for "Solar System Generator"
JOURNAL_DIR="/home/ga/.sugar/default/datastore"
JOURNAL_TITLE_FOUND="false"
if [ -d "$JOURNAL_DIR" ]; then
    MATCH=$(find "$JOURNAL_DIR" -name "title" -exec grep -il "Solar System Generator" {} \; 2>/dev/null | head -1)
    if [ -n "$MATCH" ]; then
        JOURNAL_TITLE_FOUND="true"
        echo "Found Journal entry: Solar System Generator"
    fi
fi

# Combine results
cat > /tmp/solar_system_result.json << EOF
{
    "file_modified": $FILE_MODIFIED,
    "journal_title_found": $JOURNAL_TITLE_FOUND,
    "svg_analysis": $(cat /tmp/solar_svg_analysis.json)
}
EOF

chmod 666 /tmp/solar_system_result.json
echo "Result saved to /tmp/solar_system_result.json"
cat /tmp/solar_system_result.json
echo "=== Export complete ==="