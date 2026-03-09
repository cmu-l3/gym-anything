#!/bin/bash
# Export script for Gateway Arch Catenary vs Parabola task
set -o pipefail

# Ensure fallback result on any failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": false,
    "has_cosh": false,
    "has_parabola": false,
    "has_text": false,
    "num_functions": 0,
    "error": "Export script failed"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Gateway Arch Task Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Use Python to parse the .ggb file (zip) and analyze XML content
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/gateway_arch_comparison.ggb"
TASK_START_TIME = 0
try:
    with open("/tmp/task_start_time") as f:
        TASK_START_TIME = int(f.read().strip())
except Exception:
    pass

result = {
    "file_found": False,
    "file_path": "",
    "file_size": 0,
    "file_modified": 0,
    "file_created_during_task": False,
    "task_start_time": TASK_START_TIME,
    "task_end_time": int(time.time()),
    "has_cosh": False,
    "has_parabola": False,
    "has_text": False,
    "num_functions": 0,
    "function_expressions": []
}

# Find the file (check expected path, then recent files as fallback)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Look for any recent .ggb file if expected name isn't found
    candidates = sorted(
        glob.glob("/home/ga/Documents/GeoGebra/**/*.ggb", recursive=True),
        key=os.path.getmtime, reverse=True
    )
    for c in candidates:
        if TASK_START_TIME > 0 and int(os.path.getmtime(c)) >= TASK_START_TIME:
            found_file = c
            break

if found_file:
    result["file_found"] = True
    result["file_path"] = found_file
    result["file_size"] = os.path.getsize(found_file)
    mtime = os.path.getmtime(found_file)
    result["file_modified"] = int(mtime)
    result["file_created_during_task"] = int(mtime) >= TASK_START_TIME

    try:
        with zipfile.ZipFile(found_file, 'r') as z:
            if 'geogebra.xml' in z.namelist():
                xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
                
                # Check for Function Elements
                # <element type="function" label="f">
                #   <expression label="f" exp="630 - 128 (cosh(x / 128) - 1)"/>
                # </element>
                
                # Count total functions
                result["num_functions"] = len(re.findall(r'<element type="function"', xml_content))
                
                # Check for text elements
                result["has_text"] = bool(re.search(r'<element type="text"', xml_content))

                # Extract expressions to check content
                # Search pattern for expression attributes
                expressions = re.findall(r'exp="([^"]+)"', xml_content)
                result["function_expressions"] = expressions
                
                # Also check command outputs if functions defined via commands
                # But typically simple entry uses 'expression' attribute
                
                # Analyze content for specific models
                xml_lower = xml_content.lower()
                
                # Check for Catenary (cosh)
                if 'cosh' in xml_lower:
                    result["has_cosh"] = True
                
                # Check for Parabola (x^2 or x*x or x²)
                # Common GeoGebra formats: "x^2", "x²", "x * x"
                if 'x^2' in xml_lower or 'x²' in xml_lower or 'x*x' in xml_lower or 'x * x' in xml_lower:
                    result["has_parabola"] = True
                    
                # Sanity check: ensure the parabola isn't just the cosh function misidentified
                # (unlikely given the patterns, but good to be safe)
                
    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print(json.dumps(result, indent=2))
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true