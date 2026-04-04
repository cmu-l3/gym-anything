#!/bin/bash
echo "=== Exporting titanic_survival result ==="

OMV_FILE="/home/ga/Documents/Jamovi/TitanicAnalysis.omv"
RESULT_JSON="/tmp/titanic_survival_result.json"
EXTRACT_DIR="/tmp/omv_titanic_extract"

# Take a final screenshot for evidence
SCREENSHOT="/tmp/titanic_survival_final_screenshot.png"
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
    "valid_omv": false,
    "has_index_html": false,
    "chisq_count": 0,
    "has_chisq_class": false,
    "has_chisq_sex": false,
    "has_expected_counts": false,
    "has_percentages": false,
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

# .omv files are ZIP archives — extract and parse
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
    "valid_omv": false,
    "has_index_html": false,
    "chisq_count": 0,
    "has_chisq_class": false,
    "has_chisq_sex": false,
    "has_expected_counts": false,
    "has_percentages": false,
    "error": "Failed to unzip .omv file"
}
ENDJSON
    echo "Result written to $RESULT_JSON"
    exit 0
fi

# Parse index.html with Python to extract analysis metadata
python3 << 'PYEOF'
import json
import os
import re

extract_dir = "/tmp/omv_titanic_extract"
result_json = "/tmp/titanic_survival_result.json"
omv_file = "/home/ga/Documents/Jamovi/TitanicAnalysis.omv"

result = {
    "file_exists": True,
    "file_size_bytes": os.path.getsize(omv_file),
    "valid_omv": False,
    "has_index_html": False,
    "chisq_count": 0,
    "has_chisq_class": False,
    "has_chisq_sex": False,
    "has_expected_counts": False,
    "has_percentages": False,
    "has_survived": False,
    "has_passengerclass": False,
    "has_sex": False,
    "html_snippet": "",
    "error": None,
}

# Check for expected .omv contents
expected_files = ["meta", "index.html", "xdata.json"]
found_files = []
for root, dirs, files in os.walk(extract_dir):
    for f in files:
        found_files.append(f)

if "meta" in found_files or "xdata.json" in found_files:
    result["valid_omv"] = True

# Look for index.html
index_path = os.path.join(extract_dir, "index.html")
if not os.path.exists(index_path):
    # Search recursively
    for root, dirs, files in os.walk(extract_dir):
        if "index.html" in files:
            index_path = os.path.join(root, "index.html")
            break

if os.path.exists(index_path):
    result["has_index_html"] = True

    try:
        with open(index_path, "r", encoding="utf-8-sig") as f:
            html_content = f.read()
    except UnicodeDecodeError:
        with open(index_path, "r", encoding="latin-1") as f:
            html_content = f.read()

    html_lower = html_content.lower()

    # Save a snippet for debugging (first 2000 chars)
    result["html_snippet"] = html_content[:2000]

    # Detect chi-square / contingency tables analyses
    # jamovi uses "Contingency Tables" as the analysis name
    # and shows chi-square test results with "χ²" or "Chi-square"
    chisq_indicators = [
        "contingency table",
        "chi-square",
        "chi square",
        "χ²",
        "χ<sup>2</sup>",
        "chi&#178;",
        "chisq",
    ]

    chisq_present = any(ind in html_lower for ind in chisq_indicators)

    if chisq_present:
        # Count how many separate contingency table / chi-square analyses
        # jamovi wraps each analysis in its own section
        # Look for repeated headings or analysis blocks
        # Each analysis typically has its own "Contingency Tables" heading
        ct_count = html_lower.count("contingency table")
        chisq_count = html_lower.count("χ²")
        chisq_count2 = html_lower.count("chi-square")
        chisq_count3 = html_lower.count("chi square")

        # The number of separate analyses is approximated by counting
        # distinct "Contingency Tables" headings
        # In jamovi, each analysis block starts with a heading like
        # "Contingency Tables" followed by the variable names
        result["chisq_count"] = max(1, ct_count)

        # If we see at least 2 mentions of contingency tables, assume 2 analyses
        if ct_count >= 2:
            result["chisq_count"] = ct_count

    # Check for specific variable combinations
    # Test 1: survived x passengerClass
    if ("survived" in html_lower and "passengerclass" in html_lower):
        result["has_survived"] = True
        result["has_passengerclass"] = True
        # Check if they appear together in a chi-square context
        if chisq_present:
            result["has_chisq_class"] = True

    # Test 2: survived x sex
    if ("survived" in html_lower and "sex" in html_lower):
        result["has_survived"] = True
        result["has_sex"] = True
        if chisq_present:
            result["has_chisq_sex"] = True

    # More precise: look for analysis sections containing both vars together
    # jamovi analysis blocks are wrapped in divs; look for proximity
    # Split into analysis sections and check each
    # Pattern: look for sections between analysis headings
    sections = re.split(r'<h\d[^>]*>', html_content, flags=re.IGNORECASE)
    class_section_found = False
    sex_section_found = False

    for section in sections:
        section_lower = section.lower()
        has_chisq_in_section = any(ind in section_lower for ind in chisq_indicators)

        if has_chisq_in_section or "contingency" in section_lower:
            if "survived" in section_lower and "passengerclass" in section_lower:
                class_section_found = True
            if "survived" in section_lower and "sex" in section_lower:
                sex_section_found = True

    if class_section_found:
        result["has_chisq_class"] = True
    if sex_section_found:
        result["has_chisq_sex"] = True

    # Check for expected counts
    expected_indicators = [
        "expected count",
        "expected",
    ]
    result["has_expected_counts"] = any(
        ind in html_lower for ind in expected_indicators
    )

    # Check for percentages
    pct_indicators = [
        "% within",
        "row %",
        "column %",
        "percentage",
        "% of total",
        "row percentage",
        "column percentage",
    ]
    # Also check for actual percentage signs near table data
    has_pct_indicator = any(ind in html_lower for ind in pct_indicators)
    # jamovi shows percentages with "% within" labels
    has_pct_symbol = bool(re.search(r'\d+\.?\d*\s*%', html_content))

    result["has_percentages"] = has_pct_indicator or has_pct_symbol

    print(f"Chi-square present: {chisq_present}", flush=True)
    print(f"Contingency table count: {result['chisq_count']}", flush=True)
    print(f"Class analysis found: {result['has_chisq_class']}", flush=True)
    print(f"Sex analysis found: {result['has_chisq_sex']}", flush=True)
    print(f"Expected counts: {result['has_expected_counts']}", flush=True)
    print(f"Percentages: {result['has_percentages']}", flush=True)

else:
    result["error"] = "index.html not found in .omv archive"
    print("index.html not found", flush=True)

with open(result_json, "w") as f:
    json.dump(result, f, indent=2)

print(f"Result written to {result_json}", flush=True)
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
    "valid_omv": false,
    "has_index_html": false,
    "chisq_count": 0,
    "has_chisq_class": false,
    "has_chisq_sex": false,
    "has_expected_counts": false,
    "has_percentages": false,
    "error": "Python analysis script failed"
}
ENDJSON
fi

echo "=== Export complete ==="
