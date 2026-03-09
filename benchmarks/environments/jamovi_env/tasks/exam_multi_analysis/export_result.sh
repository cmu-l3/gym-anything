#!/bin/bash
echo "=== Exporting exam_multi_analysis result ==="

OMV_FILE="/home/ga/Documents/Jamovi/ExamAnalysis.omv"
RESULT_JSON="/tmp/exam_multi_analysis_result.json"
EXTRACT_DIR="/tmp/omv_extracted"

# Take a final screenshot for evidence
SCREENSHOT="/tmp/exam_multi_analysis_final.png"
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
    "has_descriptives": false,
    "has_ttest": false,
    "has_correlation": false,
    "found_variables": [],
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
    find "$EXTRACT_DIR" -type f | head -30
else
    echo "Warning: Failed to unzip .omv file"
    cat > "$RESULT_JSON" << ENDJSON
{
    "file_exists": true,
    "file_size_bytes": ${FILE_SIZE},
    "is_valid_zip": false,
    "has_index_html": false,
    "has_descriptives": false,
    "has_ttest": false,
    "has_correlation": false,
    "found_variables": [],
    "error": "Failed to unzip .omv file"
}
ENDJSON
    echo "Result written to $RESULT_JSON"
    exit 0
fi

# Parse index.html and other contents with Python to extract analysis metadata
python3 << 'PYEOF'
import json
import os
import re
import sys

extract_dir = "/tmp/omv_extracted"
result_json = "/tmp/exam_multi_analysis_result.json"
omv_file = "/home/ga/Documents/Jamovi/ExamAnalysis.omv"

result = {
    "file_exists": True,
    "file_size_bytes": os.path.getsize(omv_file),
    "is_valid_zip": True,
    "has_index_html": False,
    "has_descriptives": False,
    "has_ttest": False,
    "has_correlation": False,
    "found_variables": [],
    "analysis_signatures": [],
    "error": None
}

# Look for index.html (jamovi stores analysis output here)
index_path = os.path.join(extract_dir, "index.html")
if not os.path.exists(index_path):
    # Walk the extracted tree to find it
    for root, dirs, files in os.walk(extract_dir):
        if "index.html" in files:
            index_path = os.path.join(root, "index.html")
            break

if os.path.exists(index_path):
    result["has_index_html"] = True
    try:
        with open(index_path, 'r', encoding='utf-8-sig') as f:
            html_content = f.read()

        html_lower = html_content.lower()

        # Check for Descriptives analysis signature
        descriptives_patterns = [
            "descriptives",
            "descriptive statistics",
            "jmv-descriptives",
            "jmvconnect-descriptives",
        ]
        for pat in descriptives_patterns:
            if pat in html_lower:
                result["has_descriptives"] = True
                result["analysis_signatures"].append(f"descriptives:{pat}")
                break

        # Check for Independent Samples T-Test signature
        ttest_patterns = [
            "independent samples t-test",
            "independent-samples t-test",
            "independentsamples",
            "jmv-ttestis",
            "ttestis",
            "t-test",
        ]
        for pat in ttest_patterns:
            if pat in html_lower:
                result["has_ttest"] = True
                result["analysis_signatures"].append(f"ttest:{pat}")
                break

        # Check for Correlation Matrix signature
        corr_patterns = [
            "correlation matrix",
            "correlation-matrix",
            "correlationmatrix",
            "jmv-corrmatrix",
            "corrmatrix",
            "pearson",
        ]
        for pat in corr_patterns:
            if pat in html_lower:
                result["has_correlation"] = True
                result["analysis_signatures"].append(f"correlation:{pat}")
                break

        # Check for expected variable names in the output
        expected_vars = ["Exam", "Revise", "Anxiety", "Gender"]
        for var in expected_vars:
            if var.lower() in html_lower:
                result["found_variables"].append(var)

        print(f"index.html analysis: descriptives={result['has_descriptives']}, "
              f"ttest={result['has_ttest']}, correlation={result['has_correlation']}", file=sys.stderr)
        print(f"Found variables: {result['found_variables']}", file=sys.stderr)

    except Exception as e:
        result["error"] = f"Failed to parse index.html: {str(e)}"
        print(f"Error parsing index.html: {e}", file=sys.stderr)
else:
    result["error"] = "index.html not found in archive"
    print("index.html not found", file=sys.stderr)

# Also check for xdata.json or meta files (jamovi internal structure)
for fname in ["xdata.json", "metadata.json", "META-INF/MANIFEST.MF"]:
    fpath = os.path.join(extract_dir, fname)
    if os.path.exists(fpath):
        print(f"Found {fname}", file=sys.stderr)

# List all files for debugging
all_files = []
for root, dirs, files in os.walk(extract_dir):
    for f in files:
        rel = os.path.relpath(os.path.join(root, f), extract_dir)
        all_files.append(rel)
result["archive_contents"] = all_files[:30]

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
    "is_valid_zip": true,
    "has_index_html": false,
    "has_descriptives": false,
    "has_ttest": false,
    "has_correlation": false,
    "found_variables": [],
    "error": "Python analysis script failed"
}
ENDJSON
fi

echo "=== Export complete ==="
