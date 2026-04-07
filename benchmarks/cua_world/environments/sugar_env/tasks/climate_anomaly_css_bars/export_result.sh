#!/bin/bash
# Export script for climate_anomaly_css_bars task

echo "=== Exporting Climate Anomaly CSS Bars Task Result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/climate_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/climate_bars_start_ts 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Documents/generate_climate_bars.py"
HTML_PATH="/home/ga/Documents/climate_bars.html"

# Initialize variables
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
SCRIPT_SIZE=0
HTML_EXISTS="false"
HTML_MODIFIED="false"
HTML_SIZE=0

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat --format=%s "$SCRIPT_PATH" 2>/dev/null || echo "0")
    SCRIPT_MTIME=$(stat --format=%Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

if [ -f "$HTML_PATH" ]; then
    HTML_EXISTS="true"
    HTML_SIZE=$(stat --format=%s "$HTML_PATH" 2>/dev/null || echo "0")
    HTML_MTIME=$(stat --format=%Y "$HTML_PATH" 2>/dev/null || echo "0")
    if [ "$HTML_MTIME" -gt "$TASK_START" ]; then
        HTML_MODIFIED="true"
    fi
    
    # Parse the HTML file with Python to evaluate DOM and CSS logic
    python3 << 'PYEOF' > /tmp/html_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/html_analysis.json
import json
import re
import os
import subprocess

html_path = "/home/ga/Documents/climate_bars.html"
result = {
    "title_present": False,
    "gt_1900": False,
    "gt_1950": False,
    "gt_2016": False,
    "has_red": False,
    "has_blue": False,
    "unique_widths": 0,
    "browse_launched": False
}

try:
    with open(html_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    
    text_lower = content.lower()
    
    # Check title
    result["title_present"] = "global temperature anomalies" in text_lower
    
    # Check ground truth values in close proximity
    # We strip tags to make searching text easier
    plain_text = re.sub(r'<[^>]+>', ' ', text_lower)
    
    # 1900 -> -0.09
    if "1900" in plain_text and "-0.09" in plain_text: result["gt_1900"] = True
    # 1950 -> -0.17
    if "1950" in plain_text and "-0.17" in plain_text: result["gt_1950"] = True
    # 2016 -> 0.99
    if "2016" in plain_text and "0.99" in plain_text: result["gt_2016"] = True
    
    # Check conditional colors
    result["has_red"] = bool(re.search(r'red|#ff0000|#f00|rgb\(255,\s*0,\s*0\)', text_lower))
    result["has_blue"] = bool(re.search(r'blue|#0000ff|#00f|rgb\(0,\s*0,\s*255\)', text_lower))
    
    # Extract CSS widths to ensure dynamic logic (not just hardcoded)
    # Match width: 120px, width:15.5%, etc.
    widths = re.findall(r'width\s*:\s*([\d\.]+)', text_lower)
    result["unique_widths"] = len(set(widths))
    
except Exception as e:
    result["error"] = str(e)

# Check if Sugar Browse was launched with this file
try:
    # Method 1: Check running processes
    ps_out = subprocess.check_output("ps aux", shell=True).decode()
    if "sugar-browse-activity" in ps_out and ("climate_bars" in ps_out or "html" in ps_out):
        result["browse_launched"] = True
    else:
        # Method 2: Check Browse logs
        log_grep = subprocess.run('grep -li "climate_bars" /home/ga/.sugar/default/logs/org.laptop.WebActivity*.log', shell=True, capture_output=True)
        if log_grep.returncode == 0 and log_grep.stdout.strip():
            result["browse_launched"] = True
except Exception:
    pass

with open("/tmp/html_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

    if [ -f /tmp/html_analysis.json ]; then
        TITLE_PRESENT=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('title_present', False)).lower())" 2>/dev/null)
        GT_1900=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('gt_1900', False)).lower())" 2>/dev/null)
        GT_1950=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('gt_1950', False)).lower())" 2>/dev/null)
        GT_2016=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('gt_2016', False)).lower())" 2>/dev/null)
        HAS_RED=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('has_red', False)).lower())" 2>/dev/null)
        HAS_BLUE=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('has_blue', False)).lower())" 2>/dev/null)
        UNIQUE_WIDTHS=$(python3 -c "import json; print(json.load(open('/tmp/html_analysis.json')).get('unique_widths', 0))" 2>/dev/null)
        BROWSE_LAUNCHED=$(python3 -c "import json; print(str(json.load(open('/tmp/html_analysis.json')).get('browse_launched', False)).lower())" 2>/dev/null)
    fi
else
    TITLE_PRESENT="false"
    GT_1900="false"
    GT_1950="false"
    GT_2016="false"
    HAS_RED="false"
    HAS_BLUE="false"
    UNIQUE_WIDTHS=0
    BROWSE_LAUNCHED="false"
fi

cat > /tmp/climate_bars_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_modified": $SCRIPT_MODIFIED,
    "script_size": $SCRIPT_SIZE,
    "html_exists": $HTML_EXISTS,
    "html_modified": $HTML_MODIFIED,
    "html_size": $HTML_SIZE,
    "title_present": ${TITLE_PRESENT:-false},
    "gt_1900": ${GT_1900:-false},
    "gt_1950": ${GT_1950:-false},
    "gt_2016": ${GT_2016:-false},
    "has_red": ${HAS_RED:-false},
    "has_blue": ${HAS_BLUE:-false},
    "unique_widths": ${UNIQUE_WIDTHS:-0},
    "browse_launched": ${BROWSE_LAUNCHED:-false}
}
EOF

chmod 666 /tmp/climate_bars_result.json
echo "Result exported to /tmp/climate_bars_result.json"
cat /tmp/climate_bars_result.json
echo "=== Export complete ==="