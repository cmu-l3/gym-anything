#!/bin/bash
# Export script for Presidential Ages Statistics task
set -o pipefail

# Ensure we always create a result file even on failure
trap 'create_fallback_result' EXIT

create_fallback_result() {
    if [ ! -f "/tmp/task_result.json" ]; then
        cat > /tmp/task_result.json << 'FALLBACK'
{
    "file_found": false,
    "file_created_during_task": false,
    "has_histogram": false,
    "has_boxplot": false,
    "has_valid_list": false,
    "list_item_count": 0,
    "found_sentinel_values": false,
    "has_median_text": false,
    "error": "Export script failed to complete"
}
FALLBACK
        chmod 666 /tmp/task_result.json 2>/dev/null || true
    fi
}

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Presidential Ages Result ==="

# 1. Take final screenshot for VLM verification
take_screenshot /tmp/task_end_screenshot.png

# 2. Run Python analysis script
# This script finds the .ggb file, extracts XML, and checks for statistical components
python3 << 'PYEOF'
import os, sys, zipfile, re, json, glob, time
import xml.etree.ElementTree as ET

EXPECTED_FILE = "/home/ga/Documents/GeoGebra/projects/presidential_ages_stats.ggb"
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
    "has_histogram": False,
    "has_boxplot": False,
    "has_valid_list": False,
    "list_item_count": 0,
    "found_sentinel_values": False, # Checks for 42 (TR), 78 (Biden)
    "has_median_text": False,
    "xml_commands": []
}

# Find the file (expected path or recent backup)
found_file = None
if os.path.exists(EXPECTED_FILE):
    found_file = EXPECTED_FILE
else:
    # Fallback: look for any .ggb file created recently
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
                
                # Parse XML to find commands and data
                commands = re.findall(r'<command name="([^"]+)"', xml_content)
                result["xml_commands"] = list(set(commands))
                
                # Check for Histogram command
                result["has_histogram"] = any(cmd.lower() == "histogram" for cmd in commands)
                
                # Check for BoxPlot command
                result["has_boxplot"] = any(cmd.lower() == "boxplot" for cmd in commands)
                
                # Check for Text containing "55" (Median)
                # GeoGebra stores text in <element type="text"> ... <startPoint ... label="55" .../> or value attributes
                # Also check expression values
                # Simple regex check for text elements containing 55
                text_elements = re.findall(r'<element type="text".*?</element>', xml_content, re.DOTALL)
                for text_el in text_elements:
                    if "55" in text_el or "Median" in text_el:
                        result["has_median_text"] = True
                        break
                
                # Advanced check: verify data list content
                # Lists are stored in <expression ... exp="{57, 61, ...}" /> OR
                # built programmatically via commands
                
                # Regex to find list definitions like exp="{57, 61, 57...}"
                # We normalize the content first
                list_pattern = re.compile(r'exp="\{([^}]+)\}"')
                matches = list_pattern.findall(xml_content)
                
                max_list_len = 0
                has_sentinels = False
                
                for match in matches:
                    # Clean up and split
                    items = [x.strip() for x in match.split(',')]
                    # Filter for numbers
                    nums = []
                    for item in items:
                        try:
                            nums.append(float(item))
                        except ValueError:
                            pass
                    
                    if len(nums) > max_list_len:
                        max_list_len = len(nums)
                        # Check for specific presidential ages: 
                        # 78 (Biden - max), 42 (TR - min), 70 (Trump)
                        # If these exist, it's likely the real dataset
                        if 78.0 in nums and 42.0 in nums and 70.0 in nums:
                            has_sentinels = True
                            
                result["list_item_count"] = max_list_len
                result["has_valid_list"] = max_list_len >= 40 # Allow for a few typos in 46 items
                result["found_sentinel_values"] = has_sentinels

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export analysis complete.")
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json