#!/bin/bash
echo "=== Exporting personality_efa result ==="

OMV_FILE="/home/ga/Documents/Jamovi/BFI_FactorAnalysis.omv"
RESULT_JSON="/tmp/personality_efa_result.json"
EXTRACT_DIR="/tmp/omv_efa_extract"

# Take a final screenshot for evidence
SCREENSHOT="/tmp/personality_efa_final_screenshot.png"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT'" 2>/dev/null || true
if [ -f "$SCREENSHOT" ]; then
    echo "Final screenshot saved: $SCREENSHOT"
else
    echo "Warning: Could not capture screenshot"
fi

# Check if the .omv file exists
if [ ! -f "$OMV_FILE" ]; then
    echo "ERROR: Output file not found: $OMV_FILE"
    cat > "$RESULT_JSON" << 'ENDJSON'
{
    "file_exists": false,
    "file_size_bytes": 0,
    "is_valid_zip": false,
    "has_index_html": false,
    "has_efa_analysis": false,
    "has_factor_loadings": false,
    "n_factors_detected": 0,
    "has_oblimin": false,
    "has_kmo": false,
    "has_bartlett": false,
    "personality_items_found": [],
    "demographic_vars_found": [],
    "error": "Output .omv file not found"
}
ENDJSON
    echo "Result written to $RESULT_JSON"
    exit 0
fi

FILE_SIZE=$(stat -c%s "$OMV_FILE" 2>/dev/null || echo 0)
echo "Found .omv file: $OMV_FILE (${FILE_SIZE} bytes)"

# Clean up previous extraction
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

# .omv files are ZIP archives -- extract and parse
if unzip -q -o "$OMV_FILE" -d "$EXTRACT_DIR" 2>/dev/null; then
    echo "Successfully extracted .omv archive"
    echo "Contents:"
    find "$EXTRACT_DIR" -type f | head -20
else
    echo "Warning: Failed to unzip .omv file"
    cat > "$RESULT_JSON" << ENDJSON
{
    "file_exists": true,
    "file_size_bytes": ${FILE_SIZE},
    "is_valid_zip": false,
    "has_index_html": false,
    "has_efa_analysis": false,
    "has_factor_loadings": false,
    "n_factors_detected": 0,
    "has_oblimin": false,
    "has_kmo": false,
    "has_bartlett": false,
    "personality_items_found": [],
    "demographic_vars_found": [],
    "error": "Failed to unzip .omv file"
}
ENDJSON
    echo "Result written to $RESULT_JSON"
    exit 0
fi

# Parse index.html with Python to extract EFA analysis metadata
python3 << 'PYEOF'
import json
import os
import re
import sys

extract_dir = "/tmp/omv_efa_extract"
result_json = "/tmp/personality_efa_result.json"
omv_file = "/home/ga/Documents/Jamovi/BFI_FactorAnalysis.omv"

result = {
    "file_exists": True,
    "file_size_bytes": os.path.getsize(omv_file),
    "is_valid_zip": True,
    "has_index_html": False,
    "has_efa_analysis": False,
    "has_factor_loadings": False,
    "n_factors_detected": 0,
    "has_oblimin": False,
    "has_kmo": False,
    "has_bartlett": False,
    "personality_items_found": [],
    "demographic_vars_found": [],
    "index_html_snippet": "",
    "error": None
}

# Look for index.html
index_path = os.path.join(extract_dir, "index.html")
if not os.path.exists(index_path):
    # Search in subdirectories
    for root, dirs, files in os.walk(extract_dir):
        if "index.html" in files:
            index_path = os.path.join(root, "index.html")
            break

if not os.path.exists(index_path):
    result["error"] = "index.html not found in .omv archive"
    print("index.html not found", file=sys.stderr)
else:
    result["has_index_html"] = True

    # Read with utf-8-sig to handle BOM
    with open(index_path, "r", encoding="utf-8-sig") as f:
        html_content = f.read()

    html_lower = html_content.lower()

    # Save a snippet for debugging (first 2000 chars)
    result["index_html_snippet"] = html_content[:2000]

    # Check for EFA / Factor Analysis presence
    efa_keywords = [
        "factor", "exploratory factor analysis", "factor loadings",
        "factor loading", "efa", "factor analysis"
    ]
    for kw in efa_keywords:
        if kw in html_lower:
            result["has_efa_analysis"] = True
            break

    # Check for factor loadings table
    loading_keywords = ["factor loading", "loadings", "uniqueness", "communalit"]
    for kw in loading_keywords:
        if kw in html_lower:
            result["has_factor_loadings"] = True
            break

    # Detect number of factors by looking for Factor 1, Factor 2, etc.
    # or column headers like "Factor 1" ... "Factor N"
    factor_nums = set()
    for m in re.finditer(r'factor\s*(\d+)', html_lower):
        factor_nums.add(int(m.group(1)))
    if factor_nums:
        result["n_factors_detected"] = max(factor_nums)

    # Check for oblimin rotation
    oblimin_keywords = ["oblimin", "oblique"]
    for kw in oblimin_keywords:
        if kw in html_lower:
            result["has_oblimin"] = True
            break

    # Check for KMO
    kmo_keywords = ["kmo", "kaiser-meyer-olkin", "sampling adequacy"]
    for kw in kmo_keywords:
        if kw in html_lower:
            result["has_kmo"] = True
            break

    # Check for Bartlett's test
    bartlett_keywords = ["bartlett", "sphericity"]
    for kw in bartlett_keywords:
        if kw in html_lower:
            result["has_bartlett"] = True
            break

    # Check which personality items appear in the output
    personality_items = [
        "A1","A2","A3","A4","A5",
        "C1","C2","C3","C4","C5",
        "E1","E2","E3","E4","E5",
        "N1","N2","N3","N4","N5",
        "O1","O2","O3","O4","O5"
    ]
    found_items = []
    for item in personality_items:
        # Look for item as a standalone token (not part of a longer string)
        if re.search(r'\b' + item + r'\b', html_content):
            found_items.append(item)
    result["personality_items_found"] = found_items

    # Check if demographic variables appear (should NOT be in factor analysis)
    demographic_vars = ["gender", "age"]
    found_demographics = []
    for var in demographic_vars:
        # Look for the var in factor loading tables (approximate check)
        if re.search(r'\b' + var + r'\b', html_lower):
            found_demographics.append(var)
    result["demographic_vars_found"] = found_demographics

    print(f"EFA analysis: {result['has_efa_analysis']}", file=sys.stderr)
    print(f"Factor loadings: {result['has_factor_loadings']}", file=sys.stderr)
    print(f"N factors detected: {result['n_factors_detected']}", file=sys.stderr)
    print(f"Oblimin: {result['has_oblimin']}", file=sys.stderr)
    print(f"KMO: {result['has_kmo']}", file=sys.stderr)
    print(f"Bartlett: {result['has_bartlett']}", file=sys.stderr)
    print(f"Personality items found: {len(found_items)}/25", file=sys.stderr)
    print(f"Demographic vars in output: {found_demographics}", file=sys.stderr)

# Also check for xdata.json (column metadata)
xdata_path = os.path.join(extract_dir, "xdata.json")
if os.path.exists(xdata_path):
    try:
        with open(xdata_path, "r", encoding="utf-8-sig") as f:
            xdata = json.load(f)
        result["has_xdata"] = True
        result["n_columns_in_data"] = len(xdata) if isinstance(xdata, list) else len(xdata.get("fields", []))
    except Exception as e:
        result["has_xdata"] = False
        print(f"Error reading xdata.json: {e}", file=sys.stderr)
else:
    result["has_xdata"] = False

with open(result_json, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {result_json}", file=sys.stderr)
PYEOF

if [ -f "$RESULT_JSON" ]; then
    echo "Export result:"
    cat "$RESULT_JSON"
else
    echo "Warning: Python analysis failed, creating minimal result"
    cat > "$RESULT_JSON" << ENDJSON
{
    "file_exists": true,
    "file_size_bytes": ${FILE_SIZE},
    "is_valid_zip": true,
    "has_index_html": false,
    "has_efa_analysis": false,
    "has_factor_loadings": false,
    "n_factors_detected": 0,
    "has_oblimin": false,
    "has_kmo": false,
    "has_bartlett": false,
    "personality_items_found": [],
    "demographic_vars_found": [],
    "error": "Python analysis script failed"
}
ENDJSON
fi

echo "=== Export complete ==="
