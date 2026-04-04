#!/bin/bash
# Export script for Lorenz Curve Gini Analysis task
set -o pipefail

# Always ensure a result file exists
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        echo "Creating fallback result due to script failure"
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "error": "Export script failed to complete normally"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

# Utilities
take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get timing info
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

# 3. Analyze the GGB file using Python
# We embed the python script to perform robust XML parsing inside the container
python3 << 'PYEOF'
import os
import sys
import zipfile
import re
import json
import time
import glob
import math

# Configuration
EXPECTED_DIR = "/home/ga/Documents/GeoGebra/projects"
EXPECTED_FILENAME = "lorenz_inequality.ggb"
TASK_START_TIME = int(os.environ.get('TASK_START_TIME', 0))

def find_task_file():
    # Try exact path first
    exact_path = os.path.join(EXPECTED_DIR, EXPECTED_FILENAME)
    if os.path.exists(exact_path):
        return exact_path
    
    # Try searching for any recently modified .ggb file in the projects dir
    files = glob.glob(os.path.join(EXPECTED_DIR, "*.ggb"))
    # Sort by modification time (newest first)
    files.sort(key=os.path.getmtime, reverse=True)
    
    if files:
        # Check if the newest file was modified after task start
        if os.path.getmtime(files[0]) >= TASK_START_TIME:
            return files[0]
    return None

def parse_ggb_xml(filepath):
    """Extracts geogebra.xml from .ggb (zip) and parses key elements."""
    data = {
        "points": [],
        "commands": [],
        "texts": [],
        "numerics": [],
        "functions": [],
        "xml_content_found": False
    }
    
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            if 'geogebra.xml' not in z.namelist():
                return data
            
            xml_content = z.read('geogebra.xml').decode('utf-8', errors='replace')
            data["xml_content_found"] = True
            
            # Simple regex parsing to avoid complex XML namespace issues
            # 1. Extract Points
            # Look for <element type="point"> ... <coords x="..." y="..." .../>
            # This is a bit complex with regex, so we iterate element blocks
            element_blocks = re.findall(r'<element type="point"[^>]*>(.*?)</element>', xml_content, re.DOTALL)
            for block in element_blocks:
                coords = re.search(r'<coords x="([^"]+)" y="([^"]+)" z="([^"]+)"', block)
                if coords:
                    try:
                        x, y, z = float(coords.group(1)), float(coords.group(2)), float(coords.group(3))
                        # Homogeneous coordinates: real x = x/z, real y = y/z
                        if abs(z) > 1e-6:
                            data["points"].append({"x": x/z, "y": y/z})
                    except ValueError:
                        pass

            # 2. Extract Commands
            # <command name="FitPoly">
            commands = re.findall(r'<command name="([^"]+)"', xml_content)
            data["commands"] = list(set(commands)) # Unique commands
            
            # 3. Extract Texts
            # <element type="text"> ... </element>
            text_blocks = re.findall(r'<element type="text"[^>]*>(.*?)</element>', xml_content, re.DOTALL)
            for block in text_blocks:
                # Text content is often in specific tag or attribute depending on version, 
                # but existence of the element is usually enough for this task.
                data["texts"].append("text_element")
                
            # 4. Extract Numeric Values (for Gini coefficient)
            # <element type="numeric"> ... <value val="0.45"/> ...
            num_blocks = re.findall(r'<element type="numeric"[^>]*>(.*?)</element>', xml_content, re.DOTALL)
            for block in num_blocks:
                val_match = re.search(r'<value val="([^"]+)"', block)
                if val_match:
                    try:
                        data["numerics"].append(float(val_match.group(1)))
                    except ValueError:
                        pass
            
            # 5. Extract Functions (to check for equality line y=x)
            # <expression label="g" exp="x" />
            expr_matches = re.findall(r'<expression [^>]*exp="([^"]+)"', xml_content)
            data["functions"] = expr_matches

    except Exception as e:
        print(f"Error parsing GGB: {e}")
        
    return data

# Main Execution
result = {
    "file_found": False,
    "file_path": "",
    "file_created_during_task": False,
    "points_found": [],
    "commands_found": [],
    "numeric_values": [],
    "functions_found": [],
    "has_text_annotation": False,
    "timestamp": time.time()
}

found_path = find_task_file()

if found_path:
    result["file_found"] = True
    result["file_path"] = found_path
    
    mtime = os.path.getmtime(found_path)
    if mtime >= TASK_START_TIME:
        result["file_created_during_task"] = True
        
    # Parse content
    parsed = parse_ggb_xml(found_path)
    result["points_found"] = parsed["points"]
    result["commands_found"] = parsed["commands"]
    result["numeric_values"] = parsed["numerics"]
    result["functions_found"] = parsed["functions"]
    result["has_text_annotation"] = len(parsed["texts"]) > 0

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Analysis complete. Result saved to /tmp/task_result.json")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="