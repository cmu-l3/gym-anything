#!/bin/bash
echo "=== Exporting exploratory_data_analysis result ==="

JASP_FILE="/home/ga/Documents/JASP/penguins_eda.jasp"
RESULT_JSON="/tmp/eda_export_result.json"
EXTRACT_DIR="/tmp/jasp_eda_extract"

# Take a final screenshot for evidence
SCREENSHOT="/tmp/eda_final_screenshot.png"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT'" 2>/dev/null || true
if [ -f "$SCREENSHOT" ]; then
    echo "Final screenshot saved: $SCREENSHOT"
else
    echo "Warning: Could not capture screenshot"
fi

# Check if the .jasp file exists
if [ ! -f "$JASP_FILE" ]; then
    echo "ERROR: Output file not found: $JASP_FILE"
    cat > "$RESULT_JSON" << 'ENDJSON'
{
    "file_exists": false,
    "file_size_bytes": 0,
    "analyses_count": 0,
    "analysis_types": [],
    "error": "Output .jasp file not found"
}
ENDJSON
    echo "Result written to $RESULT_JSON"
    exit 0
fi

FILE_SIZE=$(stat -c%s "$JASP_FILE" 2>/dev/null || echo 0)
echo "Found .jasp file: $JASP_FILE (${FILE_SIZE} bytes)"

# Clean up previous extraction
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

# .jasp files are ZIP archives — extract and parse
if unzip -q -o "$JASP_FILE" -d "$EXTRACT_DIR" 2>/dev/null; then
    echo "Successfully extracted .jasp archive"
    echo "Contents:"
    find "$EXTRACT_DIR" -type f | head -20
else
    echo "Warning: Failed to unzip .jasp file"
    cat > "$RESULT_JSON" << ENDJSON
{
    "file_exists": true,
    "file_size_bytes": ${FILE_SIZE},
    "analyses_count": 0,
    "analysis_types": [],
    "error": "Failed to unzip .jasp file"
}
ENDJSON
    echo "Result written to $RESULT_JSON"
    exit 0
fi

# Parse analyses.json with Python to extract analysis metadata
python3 << 'PYEOF'
import json
import os
import sys

extract_dir = "/tmp/jasp_eda_extract"
result_json = "/tmp/eda_export_result.json"
jasp_file = "/home/ga/Documents/JASP/penguins_eda.jasp"

result = {
    "file_exists": True,
    "file_size_bytes": os.path.getsize(jasp_file),
    "analyses_count": 0,
    "analysis_types": [],
    "analysis_details": [],
    "has_computed_results": False,
    "error": None
}

# Look for analyses.json
analyses_path = os.path.join(extract_dir, "analyses.json")
if not os.path.exists(analyses_path):
    # Try common alternative locations
    for root, dirs, files in os.walk(extract_dir):
        if "analyses.json" in files:
            analyses_path = os.path.join(root, "analyses.json")
            break

if os.path.exists(analyses_path):
    try:
        with open(analyses_path, 'r') as f:
            analyses_data = json.load(f)

        # analyses.json typically has a top-level "analyses" array
        analyses_list = []
        if isinstance(analyses_data, dict):
            analyses_list = analyses_data.get("analyses", [])
        elif isinstance(analyses_data, list):
            analyses_list = analyses_data

        result["analyses_count"] = len(analyses_list)

        for analysis in analyses_list:
            atype = analysis.get("module", analysis.get("name", "unknown"))
            aname = analysis.get("name", analysis.get("title", "unknown"))
            detail = {
                "module": analysis.get("module", ""),
                "name": aname,
                "analysis_type": analysis.get("analysisName", analysis.get("name", "")),
            }
            result["analysis_types"].append(atype)
            result["analysis_details"].append(detail)

        print(f"Found {len(analyses_list)} analyses", file=sys.stderr)

    except Exception as e:
        result["error"] = f"Failed to parse analyses.json: {str(e)}"
        print(f"Error parsing analyses.json: {e}", file=sys.stderr)
else:
    result["error"] = "analyses.json not found in archive"
    print("analyses.json not found", file=sys.stderr)

# Check for computed results (resources directory with jaspResults)
resources_dir = os.path.join(extract_dir, "resources")
if os.path.isdir(resources_dir):
    result_files = []
    for root, dirs, files in os.walk(resources_dir):
        for f in files:
            result_files.append(os.path.join(root, f))
    if result_files:
        result["has_computed_results"] = True
        print(f"Found {len(result_files)} result files in resources/", file=sys.stderr)

with open(result_json, 'w') as f:
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
    "analyses_count": 0,
    "analysis_types": [],
    "error": "Python analysis script failed"
}
ENDJSON
fi

echo "=== Export complete ==="
