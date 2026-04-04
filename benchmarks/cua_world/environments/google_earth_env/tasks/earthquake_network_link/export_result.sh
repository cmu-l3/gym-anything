#!/bin/bash
set -e
echo "=== Exporting earthquake_network_link task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ============================================================
# Capture final screenshot FIRST (before any state changes)
# ============================================================
echo "Capturing final screenshot..."
scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# ============================================================
# Check if Google Earth is still running
# ============================================================
GE_RUNNING="false"
GE_PID=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth is running (PID: $GE_PID)"
else
    echo "WARNING: Google Earth is not running"
fi

# Get window title
GE_WINDOW_TITLE=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
echo "Window title: $GE_WINDOW_TITLE"

# ============================================================
# Analyze myplaces.kml for Network Links
# ============================================================
echo "Analyzing myplaces.kml files..."

RESULT_JSON=$(python3 << 'PYTHON_EOF'
import json
import os
import xml.etree.ElementTree as ET
from datetime import datetime

EXPECTED_URL = "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.kml"
EXPECTED_KEYWORDS = ["usgs", "earthquake", "quake", "seismic", "2.5"]

def analyze_myplaces(kml_path):
    """Analyze a myplaces.kml file for Network Links."""
    result = {
        "exists": False,
        "mtime": 0,
        "network_links": [],
        "usgs_link_found": False,
        "usgs_link_details": None
    }
    
    if not os.path.exists(kml_path):
        return result
    
    result["exists"] = True
    result["mtime"] = os.path.getmtime(kml_path)
    
    try:
        tree = ET.parse(kml_path)
        root = tree.getroot()
        
        for elem in root.iter():
            if 'NetworkLink' in elem.tag:
                link_info = {
                    "name": None,
                    "href": None,
                    "visibility": "1"  # default visible
                }
                
                for child in elem.iter():
                    tag = child.tag.split('}')[-1]  # Remove namespace
                    if tag == 'name' and child.text:
                        link_info["name"] = child.text.strip()
                    elif tag == 'href' and child.text:
                        link_info["href"] = child.text.strip()
                    elif tag == 'visibility' and child.text:
                        link_info["visibility"] = child.text.strip()
                
                if link_info["href"]:
                    result["network_links"].append(link_info)
                    
                    # Check if this is the USGS earthquake link
                    if "earthquake.usgs.gov" in link_info["href"]:
                        result["usgs_link_found"] = True
                        result["usgs_link_details"] = link_info
                        
    except ET.ParseError as e:
        result["parse_error"] = str(e)
    except Exception as e:
        result["error"] = str(e)
    
    return result

# Load initial state
initial_state = {}
try:
    with open("/tmp/initial_network_links.json", "r") as f:
        initial_state = json.load(f)
except:
    pass

# Analyze current state
paths = [
    "/home/ga/.googleearth/myplaces.kml",
    "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
]

final_state = {
    "timestamp": datetime.now().isoformat(),
    "paths": {}
}

usgs_link_found = False
usgs_link_details = None
file_modified_during_task = False
task_start = float(os.environ.get("TASK_START", "0"))

for path in paths:
    analysis = analyze_myplaces(path)
    final_state["paths"][path] = analysis
    
    if analysis["usgs_link_found"]:
        usgs_link_found = True
        usgs_link_details = analysis["usgs_link_details"]
    
    # Check if file was modified during task
    if analysis["exists"] and analysis["mtime"] > task_start:
        file_modified_during_task = True

# Check name quality
name_has_keywords = False
if usgs_link_details and usgs_link_details.get("name"):
    name_lower = usgs_link_details["name"].lower()
    name_has_keywords = any(kw in name_lower for kw in EXPECTED_KEYWORDS)

# Check URL correctness
url_correct = False
url_partial = False
if usgs_link_details and usgs_link_details.get("href"):
    href = usgs_link_details["href"]
    url_correct = EXPECTED_URL in href or href == EXPECTED_URL
    url_partial = "earthquake.usgs.gov" in href

# Build result
result = {
    "usgs_link_found": usgs_link_found,
    "usgs_link_details": usgs_link_details,
    "url_correct": url_correct,
    "url_partial_match": url_partial,
    "name_has_keywords": name_has_keywords,
    "file_modified_during_task": file_modified_during_task,
    "total_network_links": sum(len(v.get("network_links", [])) for v in final_state["paths"].values()),
    "paths_analyzed": final_state["paths"],
    "initial_state": initial_state.get("paths", {})
}

print(json.dumps(result))
PYTHON_EOF
)

echo "Analysis result: $RESULT_JSON"

# Parse key values from Python output
USGS_FOUND=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('usgs_link_found', False))" 2>/dev/null || echo "false")
URL_CORRECT=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url_correct', False))" 2>/dev/null || echo "false")
NAME_GOOD=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('name_has_keywords', False))" 2>/dev/null || echo "false")
FILE_MODIFIED=$(echo "$RESULT_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('file_modified_during_task', False))" 2>/dev/null || echo "false")

# ============================================================
# Create final result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "window_title": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "usgs_link_found": $USGS_FOUND,
    "url_correct": $URL_CORRECT,
    "name_has_keywords": $NAME_GOOD,
    "file_modified_during_task": $FILE_MODIFIED,
    "kml_analysis": $RESULT_JSON
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json