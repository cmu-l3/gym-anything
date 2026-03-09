#!/bin/bash
echo "=== Exporting tooth_growth_factorial result ==="

OMV_OUTPUT="/home/ga/Documents/Jamovi/ToothGrowthAnalysis.omv"
EXTRACT_DIR="/tmp/jamovi_anova_extract"
RESULT_JSON="/tmp/tooth_growth_factorial_result.json"

# ------------------------------------------------------------------
# Take a screenshot of the final state
# ------------------------------------------------------------------
SCREENSHOT_PATH="/tmp/tooth_growth_factorial_screenshot.png"
rm -f "$SCREENSHOT_PATH" 2>/dev/null || true
su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot '$SCREENSHOT_PATH'" 2>/dev/null || true
if [ -f "$SCREENSHOT_PATH" ]; then
    echo "Screenshot saved: $SCREENSHOT_PATH"
else
    echo "Warning: Could not capture screenshot"
fi

# ------------------------------------------------------------------
# Check if the .omv output file exists
# ------------------------------------------------------------------
if [ ! -f "$OMV_OUTPUT" ]; then
    echo "WARNING: .omv file not found at $OMV_OUTPUT"
    cat > "$RESULT_JSON" << 'EOJSON'
{
  "omv_file_exists": false,
  "omv_file_size": 0,
  "has_index_html": false,
  "has_anova": false,
  "has_interaction": false,
  "has_homogeneity": false,
  "has_normality": false,
  "has_posthoc": false,
  "has_descriptives": false,
  "has_len": false,
  "has_supp": false,
  "has_dose": false,
  "error": "No .omv file found at expected path"
}
EOJSON
    echo "Result JSON written to $RESULT_JSON"
    echo "=== Export complete (no .omv file) ==="
    exit 0
fi

FILE_SIZE=$(stat -c%s "$OMV_OUTPUT" 2>/dev/null || echo 0)
echo ".omv file found: $OMV_OUTPUT ($FILE_SIZE bytes)"

# ------------------------------------------------------------------
# jamovi saves .omv files as ZIP archives. Extract and parse.
# ------------------------------------------------------------------
rm -rf "$EXTRACT_DIR" 2>/dev/null || true
mkdir -p "$EXTRACT_DIR"

if ! unzip -q -o "$OMV_OUTPUT" -d "$EXTRACT_DIR" 2>/dev/null; then
    echo "WARNING: Failed to unzip .omv file"
    cat > "$RESULT_JSON" << EOJSON
{
  "omv_file_exists": true,
  "omv_file_size": $FILE_SIZE,
  "has_index_html": false,
  "has_anova": false,
  "has_interaction": false,
  "has_homogeneity": false,
  "has_normality": false,
  "has_posthoc": false,
  "has_descriptives": false,
  "has_len": false,
  "has_supp": false,
  "has_dose": false,
  "error": "Failed to unzip .omv file"
}
EOJSON
    echo "=== Export complete (unzip failed) ==="
    exit 0
fi

echo "Extracted .omv contents:"
ls -la "$EXTRACT_DIR"/

# ------------------------------------------------------------------
# Parse index.html to detect analysis components.
# jamovi stores analysis output as rendered HTML in index.html.
# We search for keywords that indicate the required analyses.
# ------------------------------------------------------------------
INDEX_HTML="$EXTRACT_DIR/index.html"
if [ ! -f "$INDEX_HTML" ]; then
    echo "WARNING: index.html not found in .omv archive"
    cat > "$RESULT_JSON" << EOJSON
{
  "omv_file_exists": true,
  "omv_file_size": $FILE_SIZE,
  "has_index_html": false,
  "has_anova": false,
  "has_interaction": false,
  "has_homogeneity": false,
  "has_normality": false,
  "has_posthoc": false,
  "has_descriptives": false,
  "has_len": false,
  "has_supp": false,
  "has_dose": false,
  "error": "index.html not found in .omv archive"
}
EOJSON
    echo "=== Export complete (no index.html) ==="
    exit 0
fi

echo "index.html found. Parsing with Python..."

python3 << 'PYEOF'
import json
import os
import re

EXTRACT_DIR = "/tmp/jamovi_anova_extract"
RESULT_JSON = "/tmp/tooth_growth_factorial_result.json"
OMV_OUTPUT = "/home/ga/Documents/Jamovi/ToothGrowthAnalysis.omv"

try:
    file_size = os.path.getsize(OMV_OUTPUT)
except OSError:
    file_size = 0

index_path = os.path.join(EXTRACT_DIR, "index.html")

result = {
    "omv_file_exists": True,
    "omv_file_size": file_size,
    "has_index_html": False,
    "has_anova": False,
    "has_interaction": False,
    "has_homogeneity": False,
    "has_normality": False,
    "has_posthoc": False,
    "has_descriptives": False,
    "has_len": False,
    "has_supp": False,
    "has_dose": False,
    "archive_files": [],
    "index_html_size": 0,
    "error": None
}

try:
    # List all files in the extracted archive
    for root, dirs, files in os.walk(EXTRACT_DIR):
        for fname in files:
            rel = os.path.relpath(os.path.join(root, fname), EXTRACT_DIR)
            result["archive_files"].append(rel)

    # Read index.html
    with open(index_path, "r", encoding="utf-8-sig") as f:
        html_content = f.read()

    result["has_index_html"] = True
    result["index_html_size"] = len(html_content)

    # Case-insensitive search through the HTML content
    html_lower = html_content.lower()

    # Check for ANOVA analysis
    # jamovi renders "ANOVA" in table headers and titles
    result["has_anova"] = bool(
        re.search(r'anova', html_lower)
    )

    # Check for interaction term: supp:dose, supp*dose, supp x dose,
    # or the unicode multiply sign supp✻dose
    result["has_interaction"] = bool(
        re.search(r'supp\s*[\*:×✻]\s*dose', html_lower) or
        re.search(r'dose\s*[\*:×✻]\s*supp', html_lower) or
        re.search(r'supp\s*\u2731\s*dose', html_lower) or
        re.search(r'dose\s*\u2731\s*supp', html_lower)
    )

    # Check for homogeneity of variances test (Levene's test)
    result["has_homogeneity"] = bool(
        re.search(r'homogeneity', html_lower) or
        re.search(r'levene', html_lower)
    )

    # Check for normality test (Shapiro-Wilk or Q-Q plot reference)
    result["has_normality"] = bool(
        re.search(r'normality', html_lower) or
        re.search(r'shapiro', html_lower) or
        re.search(r'q-q\s*plot', html_lower)
    )

    # Check for Post Hoc comparisons
    result["has_posthoc"] = bool(
        re.search(r'post\s*hoc', html_lower) or
        re.search(r'tukey', html_lower) or
        re.search(r'post-hoc', html_lower)
    )

    # Check for descriptives table
    result["has_descriptives"] = bool(
        re.search(r'descriptive', html_lower)
    )

    # Check for variable names in the analysis
    result["has_len"] = bool(re.search(r'\blen\b', html_lower))
    result["has_supp"] = bool(re.search(r'\bsupp\b', html_lower))
    result["has_dose"] = bool(re.search(r'\bdose\b', html_lower))

    # Also try to parse any JSON analysis files in the archive
    # (jamovi may store analysis configs alongside HTML)
    for fname in result["archive_files"]:
        if fname.endswith(".json") and fname != "xdata.json":
            try:
                fpath = os.path.join(EXTRACT_DIR, fname)
                with open(fpath, "r", encoding="utf-8-sig") as jf:
                    jdata = json.load(jf)
                # Store analysis JSON filenames for debugging
                if "analyses" not in result:
                    result["analysis_json_files"] = []
                result["analysis_json_files"].append(fname)
            except Exception:
                pass

except Exception as e:
    result["error"] = str(e)

# Write result
with open(RESULT_JSON, "w") as f:
    json.dump(result, f, indent=2, default=str)

print(f"Result written to {RESULT_JSON}")
print(f"  .omv file size: {result['omv_file_size']} bytes")
print(f"  index.html size: {result['index_html_size']} chars")
print(f"  ANOVA found: {result['has_anova']}")
print(f"  Interaction: {result['has_interaction']}")
print(f"  Homogeneity: {result['has_homogeneity']}")
print(f"  Normality: {result['has_normality']}")
print(f"  Post-hoc: {result['has_posthoc']}")
print(f"  Descriptives: {result['has_descriptives']}")
print(f"  Variables - len: {result['has_len']}, supp: {result['has_supp']}, dose: {result['has_dose']}")
print(f"  Archive files: {result['archive_files']}")
PYEOF

echo ""
echo "=== tooth_growth_factorial export complete ==="
