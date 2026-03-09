#!/bin/bash
echo "=== Exporting factorial_anova_analysis result ==="

JASP_OUTPUT="/home/ga/Documents/JASP/tooth_growth_anova.jasp"
EXTRACT_DIR="/tmp/jasp_anova_extract"
RESULT_JSON="/tmp/factorial_anova_result.json"

# ------------------------------------------------------------------
# Take a screenshot of the final state
# ------------------------------------------------------------------
SCREENSHOT_PATH="/tmp/factorial_anova_screenshot.png"
rm -f "$SCREENSHOT_PATH" 2>/dev/null || true
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT_PATH'" 2>/dev/null || true
if [ -f "$SCREENSHOT_PATH" ]; then
    echo "Screenshot saved: $SCREENSHOT_PATH"
else
    echo "Warning: Could not capture screenshot"
fi

# ------------------------------------------------------------------
# Check if the .jasp output file exists
# ------------------------------------------------------------------
if [ ! -f "$JASP_OUTPUT" ]; then
    echo "WARNING: .jasp file not found at $JASP_OUTPUT"
    # Write a minimal result JSON indicating no output
    cat > "$RESULT_JSON" << 'EOJSON'
{
  "jasp_file_exists": false,
  "jasp_file_size": 0,
  "analyses_found": false,
  "analysis_count": 0,
  "analyses": [],
  "error": "No .jasp file found at expected path"
}
EOJSON
    echo "Result JSON written to $RESULT_JSON"
    echo "=== Export complete (no .jasp file) ==="
    exit 0
fi

FILE_SIZE=$(stat -c%s "$JASP_OUTPUT" 2>/dev/null || echo 0)
echo ".jasp file found: $JASP_OUTPUT ($FILE_SIZE bytes)"

# ------------------------------------------------------------------
# JASP saves .jasp files as ZIP archives. Extract and parse.
# ------------------------------------------------------------------
rm -rf "$EXTRACT_DIR" 2>/dev/null || true
mkdir -p "$EXTRACT_DIR"

if ! unzip -q -o "$JASP_OUTPUT" -d "$EXTRACT_DIR" 2>/dev/null; then
    echo "WARNING: Failed to unzip .jasp file"
    cat > "$RESULT_JSON" << EOJSON
{
  "jasp_file_exists": true,
  "jasp_file_size": $FILE_SIZE,
  "analyses_found": false,
  "analysis_count": 0,
  "analyses": [],
  "error": "Failed to unzip .jasp file"
}
EOJSON
    echo "=== Export complete (unzip failed) ==="
    exit 0
fi

echo "Extracted .jasp contents:"
ls -la "$EXTRACT_DIR"/

# ------------------------------------------------------------------
# Parse analyses.json with Python to extract analysis details
# ------------------------------------------------------------------
ANALYSES_JSON="$EXTRACT_DIR/analyses.json"
if [ ! -f "$ANALYSES_JSON" ]; then
    echo "WARNING: analyses.json not found in .jasp archive"
    cat > "$RESULT_JSON" << EOJSON
{
  "jasp_file_exists": true,
  "jasp_file_size": $FILE_SIZE,
  "analyses_found": false,
  "analysis_count": 0,
  "analyses": [],
  "error": "analyses.json not found in .jasp archive"
}
EOJSON
    echo "=== Export complete (no analyses.json) ==="
    exit 0
fi

echo "analyses.json found. Parsing with Python..."

python3 << 'PYEOF'
import json
import os
import sys

EXTRACT_DIR = "/tmp/jasp_anova_extract"
RESULT_JSON = "/tmp/factorial_anova_result.json"
JASP_OUTPUT = "/home/ga/Documents/JASP/tooth_growth_anova.jasp"

try:
    file_size = os.path.getsize(JASP_OUTPUT)
except OSError:
    file_size = 0

analyses_path = os.path.join(EXTRACT_DIR, "analyses.json")

result = {
    "jasp_file_exists": True,
    "jasp_file_size": file_size,
    "analyses_found": False,
    "analysis_count": 0,
    "analyses": [],
    "raw_analyses_json": None,
    "error": None
}

try:
    with open(analyses_path, "r") as f:
        analyses_data = json.load(f)

    # Store the raw JSON for the verifier
    result["raw_analyses_json"] = analyses_data

    # analyses.json is typically a list of analysis objects
    if isinstance(analyses_data, list):
        analysis_list = analyses_data
    elif isinstance(analyses_data, dict) and "analyses" in analyses_data:
        analysis_list = analyses_data["analyses"]
    else:
        analysis_list = [analyses_data] if isinstance(analyses_data, dict) else []

    result["analyses_found"] = len(analysis_list) > 0
    result["analysis_count"] = len(analysis_list)

    for i, analysis in enumerate(analysis_list):
        if not isinstance(analysis, dict):
            continue

        info = {
            "index": i,
            "name": analysis.get("name", ""),
            "analysis_type": analysis.get("analysisType", analysis.get("type", "")),
            "module": analysis.get("module", ""),
        }

        # Extract options (the analysis configuration)
        options = analysis.get("options", {})
        if isinstance(options, dict):
            info["dependent_variable"] = options.get("dependent", options.get("dependentVariable", ""))
            info["fixed_factors"] = options.get("fixedFactors", [])
            info["random_factors"] = options.get("randomFactors", [])
            info["post_hoc_terms"] = options.get("postHocTerms", options.get("postHocTestsVariables", []))

            # Check for descriptive statistics
            info["descriptives"] = options.get("descriptives", False)

            # Check for descriptive plots
            info["descriptive_plots"] = options.get("descriptivePlots", {})
            info["plot_horizontal_axis"] = options.get("plotHorizontalAxis", "")
            info["plot_separate_lines"] = options.get("plotSeparateLines", "")
            info["plot_separate_plots"] = options.get("plotSeparatePlots", "")

            # Check for effect sizes
            info["effect_size_eta_squared"] = options.get("effectSizeEtaSquared", False)
            info["effect_size_partial_eta_squared"] = options.get("effectSizePartialEtaSquared", False)
            info["effect_size_omega_squared"] = options.get("effectSizeOmegaSquared", False)

            # Store the full options for deeper inspection
            info["options_keys"] = list(options.keys())
            info["full_options"] = options

        result["analyses"].append(info)

except Exception as e:
    result["error"] = str(e)

# Write result
with open(RESULT_JSON, "w") as f:
    json.dump(result, f, indent=2, default=str)

print(f"Result written to {RESULT_JSON}")
print(f"  Analyses found: {result['analysis_count']}")
for a in result["analyses"]:
    print(f"  - [{a['index']}] {a['name']} ({a['analysis_type']}, module={a['module']})")
    print(f"    DV: {a.get('dependent_variable')}, Factors: {a.get('fixed_factors')}")
    print(f"    Post-hoc: {a.get('post_hoc_terms')}")
    print(f"    Descriptives: {a.get('descriptives')}")
    print(f"    Eta-squared: {a.get('effect_size_eta_squared')}")
PYEOF

# ------------------------------------------------------------------
# Also check for computed results in resources directory
# ------------------------------------------------------------------
if [ -d "$EXTRACT_DIR/resources" ]; then
    echo ""
    echo "Resources directory contents:"
    find "$EXTRACT_DIR/resources" -name "*.json" -type f 2>/dev/null | head -10
    RESOURCE_COUNT=$(find "$EXTRACT_DIR/resources" -name "*.json" -type f 2>/dev/null | wc -l)
    echo "Total resource JSON files: $RESOURCE_COUNT"
else
    echo "No resources directory found in .jasp archive"
fi

echo ""
echo "=== factorial_anova_analysis export complete ==="
