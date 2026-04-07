#!/bin/bash
echo "=== Exporting Growth Curve Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Find results file
RESULTS_FILE="/home/ga/AstroImages/measurements/growth_curve_results.txt"
RESULTS_CONTENT=""
RESULTS_EXIST="false"
RESULTS_MTIME=0

if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXIST="true"
    RESULTS_CONTENT=$(head -n 50 "$RESULTS_FILE")
    RESULTS_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
else
    # Check alternate possible locations
    ALT_FILE=$(find /home/ga -name "*growth_curve*.txt" -o -name "*results*.txt" 2>/dev/null | grep -v "/\." | head -1)
    if [ -n "$ALT_FILE" ] && [ -f "$ALT_FILE" ]; then
        RESULTS_EXIST="true"
        RESULTS_CONTENT=$(head -n 50 "$ALT_FILE")
        RESULTS_MTIME=$(stat -c %Y "$ALT_FILE" 2>/dev/null || echo "0")
        RESULTS_FILE="$ALT_FILE"
    fi
fi

# Extract and parse in Python
python3 << PYEOF
import json
import re

content = """$RESULTS_CONTENT"""
mtime = $RESULTS_MTIME

result = {
    "results_exist": "$RESULTS_EXIST" == "true",
    "mtime": mtime,
    "measurements": {},
    "optimal_aperture": None
}

if result["results_exist"]:
    # Parse measurements
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
            
        # Ignore optimal aperture line for the measurement dictionary
        if "optimal" in line.lower() or "radius" in line.lower() and ":" in line:
            pass
        else:
            # Extract two numbers
            parts = re.findall(r'[-+]?\d*\.\d+|\d+', line)
            if len(parts) >= 2:
                try:
                    r = float(parts[0])
                    f = float(parts[1])
                    if r <= 100:  # Reasonable radius
                        result["measurements"][str(r)] = f
                except:
                    pass

    # Parse optimal aperture
    m_opt = re.search(r'optimal(?: aperture)?(?: radius)?[\s:=]+(\d+(?:\.\d+)?)', content, re.IGNORECASE)
    if m_opt:
        try:
            result["optimal_aperture"] = float(m_opt.group(1))
        except:
            pass

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Exported results:"
cat /tmp/task_result.json

echo "=== Export Complete ==="