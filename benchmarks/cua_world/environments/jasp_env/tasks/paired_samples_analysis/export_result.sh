#!/bin/bash
echo "=== Exporting paired_samples_analysis result ==="

# Take final screenshot
SCREENSHOT_PATH="/tmp/paired_samples_analysis_final.png"
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT_PATH'" 2>/dev/null || \
    DISPLAY=:1 xwd -root -silent | convert xwd:- png:"$SCREENSHOT_PATH" 2>/dev/null || true

if [ -f "$SCREENSHOT_PATH" ]; then
    echo "Final screenshot saved: $SCREENSHOT_PATH ($(stat -c%s "$SCREENSHOT_PATH") bytes)"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Check if the .jasp output file exists
OUTPUT_FILE="/home/ga/Documents/JASP/weight_gain_analysis.jasp"
RESULT_JSON="/tmp/paired_samples_analysis_result.json"

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "ERROR: Output file not found: $OUTPUT_FILE"
    cat > "$RESULT_JSON" << 'EOF'
{
    "file_exists": false,
    "error": "Output .jasp file not found",
    "analyses_count": 0,
    "analysis_types": [],
    "variables": [],
    "options": {}
}
EOF
    echo "Result JSON written to $RESULT_JSON"
    echo "=== Export complete (no output file) ==="
    exit 0
fi

FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
echo "Output file found: $OUTPUT_FILE ($FILE_SIZE bytes)"

# Unzip the .jasp file (it's a ZIP archive) and extract analysis metadata
EXTRACT_DIR="/tmp/jasp_analysis"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

if unzip -o "$OUTPUT_FILE" -d "$EXTRACT_DIR" > /dev/null 2>&1; then
    echo "Successfully unzipped .jasp file to $EXTRACT_DIR"
    echo "Contents:"
    find "$EXTRACT_DIR" -type f | head -20
else
    echo "ERROR: Failed to unzip .jasp file"
    cat > "$RESULT_JSON" << EOF
{
    "file_exists": true,
    "file_size": $FILE_SIZE,
    "error": "Failed to unzip .jasp file",
    "analyses_count": 0,
    "analysis_types": [],
    "variables": [],
    "options": {}
}
EOF
    echo "=== Export complete (unzip failed) ==="
    exit 0
fi

# Parse analyses.json and jaspResults.json using Python
python3 << 'PYEOF'
import json
import os
import glob

extract_dir = "/tmp/jasp_analysis"
result = {
    "file_exists": True,
    "file_size": 0,
    "analyses_count": 0,
    "analysis_types": [],
    "variable_assignments": {},
    "options_enabled": {},
    "computed_results": {}
}

# File size
output_file = "/home/ga/Documents/JASP/weight_gain_analysis.jasp"
try:
    result["file_size"] = os.path.getsize(output_file)
except:
    pass

# Parse analyses.json
analyses_path = os.path.join(extract_dir, "analyses.json")
if os.path.exists(analyses_path):
    try:
        with open(analyses_path, 'r') as f:
            analyses_data = json.load(f)

        analyses = analyses_data if isinstance(analyses_data, list) else analyses_data.get("analyses", [])
        result["analyses_count"] = len(analyses)

        for i, analysis in enumerate(analyses):
            atype = analysis.get("name", analysis.get("module", "unknown"))
            result["analysis_types"].append(atype)

            opts = analysis.get("options", {})

            # Extract variable assignments
            var_info = {}
            for key in ["pairs", "variables", "dependent", "groupingVariable",
                         "dependentVariables", "fixedFactors"]:
                if key in opts and opts[key]:
                    var_info[key] = opts[key]
            if var_info:
                result["variable_assignments"][f"analysis_{i}_{atype}"] = var_info

            # Extract enabled options
            opt_info = {}
            for key in ["effectSize", "effectSizeCI", "descriptives",
                         "meanDifference", "meanDifferenceCI",
                         "students", "wilcoxon", "mannWhitney",
                         "effectSizeType", "descriptivesPlots"]:
                if key in opts:
                    opt_info[key] = opts[key]
            # Check statistics sub-options
            if "statistics" in opts:
                opt_info["statistics"] = opts["statistics"]
            if opt_info:
                result["options_enabled"][f"analysis_{i}_{atype}"] = opt_info

        print(f"Found {result['analyses_count']} analyses: {result['analysis_types']}")
    except Exception as e:
        result["parse_error"] = str(e)
        print(f"Error parsing analyses.json: {e}")
else:
    print("WARNING: analyses.json not found in extracted .jasp")
    result["parse_error"] = "analyses.json not found"

# Look for jaspResults.json files (computed results)
results_files = glob.glob(os.path.join(extract_dir, "resources", "*", "jaspResults.json"))
for rf in results_files:
    try:
        with open(rf, 'r') as f:
            rdata = json.load(f)
        resource_id = os.path.basename(os.path.dirname(rf))
        # Extract key computed values
        result["computed_results"][resource_id] = {
            "has_data": True,
            "keys": list(rdata.keys())[:10] if isinstance(rdata, dict) else "list"
        }
        print(f"Found computed results in: {rf}")
    except Exception as e:
        print(f"Error reading {rf}: {e}")

# Write result JSON
with open("/tmp/paired_samples_analysis_result.json", 'w') as f:
    json.dump(result, f, indent=2, default=str)

print(f"\nSummary: {result['analyses_count']} analyses, "
      f"{len(result['computed_results'])} result files, "
      f"file size: {result['file_size']} bytes")
PYEOF

echo ""
echo "Result JSON written to $RESULT_JSON"
if [ -f "$RESULT_JSON" ]; then
    cat "$RESULT_JSON"
fi

echo "=== Export complete ==="
