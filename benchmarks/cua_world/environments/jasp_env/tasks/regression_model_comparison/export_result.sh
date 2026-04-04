#!/bin/bash
echo "=== Exporting regression_model_comparison result ==="

RESULT_FILE="/tmp/regression_model_comparison_result.json"
JASP_FILE="/home/ga/Documents/JASP/happiness_regression.jasp"
SCREENSHOT="/tmp/regression_model_comparison_screenshot.png"

# ============================================================
# Take a screenshot of the current JASP state
# ============================================================
su - ga -c "DISPLAY=:1 scrot '$SCREENSHOT'" 2>/dev/null || true
if [ -f "$SCREENSHOT" ]; then
    echo "Screenshot saved: $SCREENSHOT ($(stat -c%s "$SCREENSHOT") bytes)"
else
    echo "Warning: Screenshot capture failed"
fi

# ============================================================
# Check if the .jasp file exists
# ============================================================
if [ ! -f "$JASP_FILE" ]; then
    echo "WARNING: JASP file not found at $JASP_FILE"
    # Write a minimal result so verifier can report the failure
    cat > "$RESULT_FILE" << 'NORESULT'
{
    "jasp_file_exists": false,
    "jasp_file_size": 0,
    "analyses": [],
    "error": "JASP file not found at expected path"
}
NORESULT
    echo "=== Export complete (file not found) ==="
    exit 0
fi

JASP_SIZE=$(stat -c%s "$JASP_FILE" 2>/dev/null || echo 0)
echo "JASP file found: $JASP_FILE (${JASP_SIZE} bytes)"

# ============================================================
# Unzip and parse the .jasp file (it's a ZIP archive)
# Extract analyses.json and any jaspResults.json files
# ============================================================
EXTRACT_DIR="/tmp/jasp_extract_regression"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

if ! unzip -o "$JASP_FILE" -d "$EXTRACT_DIR" > /dev/null 2>&1; then
    echo "WARNING: Failed to unzip JASP file"
    cat > "$RESULT_FILE" << UNZIPERR
{
    "jasp_file_exists": true,
    "jasp_file_size": ${JASP_SIZE},
    "analyses": [],
    "error": "Failed to unzip JASP file"
}
UNZIPERR
    echo "=== Export complete (unzip failed) ==="
    exit 0
fi

echo "JASP file extracted to $EXTRACT_DIR"
ls -la "$EXTRACT_DIR/" 2>/dev/null || true

# ============================================================
# Parse analyses.json with Python to extract analysis details
# ============================================================
python3 << 'PYEOF'
import json
import os
import glob
import sys

extract_dir = "/tmp/jasp_extract_regression"
result_file = "/tmp/regression_model_comparison_result.json"
jasp_file = "/home/ga/Documents/JASP/happiness_regression.jasp"

result = {
    "jasp_file_exists": True,
    "jasp_file_size": os.path.getsize(jasp_file),
    "analyses": [],
    "analyses_raw": None,
    "jasp_results_files": [],
    "error": None
}

# Read analyses.json
analyses_path = os.path.join(extract_dir, "analyses.json")
if not os.path.exists(analyses_path):
    result["error"] = "analyses.json not found in JASP archive"
    with open(result_file, "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

try:
    with open(analyses_path, "r") as f:
        analyses_data = json.load(f)
except Exception as e:
    result["error"] = f"Failed to parse analyses.json: {str(e)}"
    with open(result_file, "w") as f:
        json.dump(result, f, indent=2)
    sys.exit(0)

result["analyses_raw"] = analyses_data

# Extract analysis entries -- JASP stores them under "analyses" key
analyses_list = []
if isinstance(analyses_data, dict):
    analyses_list = analyses_data.get("analyses", [])
elif isinstance(analyses_data, list):
    analyses_list = analyses_data

for analysis in analyses_list:
    entry = {
        "name": analysis.get("name", ""),
        "module": analysis.get("module", ""),
        "analysis": analysis.get("analysis", ""),
        "options": analysis.get("options", {}),
        "title": analysis.get("title", ""),
        "id": analysis.get("id", ""),
    }
    result["analyses"].append(entry)

# Find all jaspResults.json files (computed results)
jasp_results = glob.glob(os.path.join(extract_dir, "resources", "**", "jaspResults.json"), recursive=True)
for rpath in jasp_results:
    try:
        with open(rpath, "r") as f:
            rdata = json.load(f)
        result["jasp_results_files"].append({
            "path": rpath.replace(extract_dir, ""),
            "size": os.path.getsize(rpath),
            "keys": list(rdata.keys()) if isinstance(rdata, dict) else "not_dict"
        })
    except Exception as e:
        result["jasp_results_files"].append({
            "path": rpath.replace(extract_dir, ""),
            "error": str(e)
        })

# Write result
with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {result_file}")
print(f"Found {len(result['analyses'])} analyses")
print(f"Found {len(result['jasp_results_files'])} jaspResults.json files")
PYEOF

if [ -f "$RESULT_FILE" ]; then
    echo "Result file: $RESULT_FILE ($(stat -c%s "$RESULT_FILE") bytes)"
else
    echo "ERROR: Result file was not created"
fi

echo "=== regression_model_comparison export complete ==="
