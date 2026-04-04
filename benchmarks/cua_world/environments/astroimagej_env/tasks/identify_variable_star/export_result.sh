#!/bin/bash
# Export script for Identify Variable Star task
# Extracts analysis results from AstroImageJ for verification
#
# Searches for:
# - Measurement files (.xls, .csv, .tbl) with multi-star photometry data
# - Report file (variable_star_report.txt) identifying the variable star
#
# Key difference from detect_exoplanet_transit: this task checks whether
# the agent IDENTIFIED the correct variable star, not whether they fitted
# a transit model. The transit depth is ~1.4% (real WASP-12b data).

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting Variable Star Identification Results ==="

# Take final screenshot
FINAL_SCREENSHOT="/tmp/aij_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT" 2>/dev/null || DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || true
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# Get window list
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Windows: $WINDOWS_LIST"

LIGHTCURVE_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "plot\|Multi-plot\|Measurements\|curve"; then
    LIGHTCURVE_WINDOW="true"
    echo "Light curve/plot window detected"
fi

MULTIAP_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "Multi-Aperture\|Aperture"; then
    MULTIAP_WINDOW="true"
    echo "Multi-aperture window detected"
fi

# ============================================================
# Find measurement files
# ============================================================
echo ""
echo "=== Searching for measurement files ==="

PROJECT_DIR="/home/ga/AstroImages/variable_search"
SEARCH_DIRS="$PROJECT_DIR /home/ga/AstroImages /home/ga /home/ga/Desktop"

MEASUREMENT_FILE=""
MEASUREMENT_FILES_FOUND=""

for dir in $SEARCH_DIRS; do
    if [ -d "$dir" ]; then
        found=$(find "$dir" -maxdepth 2 -type f \( \
            -name "*Measurements*.xls" -o \
            -name "*Measurements*.tbl" -o \
            -name "*Measurements*.csv" -o \
            -name "*_T1*.xls" -o \
            -name "*photometry*.txt" -o \
            -name "*photometry*.csv" -o \
            -name "*lightcurve*.txt" -o \
            -name "measurements.*" \
        \) 2>/dev/null | head -5)

        if [ -n "$found" ]; then
            echo "Found in $dir:"
            echo "$found"
            MEASUREMENT_FILES_FOUND="$MEASUREMENT_FILES_FOUND $found"

            if [ -z "$MEASUREMENT_FILE" ]; then
                MEASUREMENT_FILE=$(echo "$found" | head -1)
            fi
        fi
    fi
done

# Also check for any new .xls or .tbl files since task start
BASELINE_TIME="/tmp/initial_measurement_count"
if [ -f "$BASELINE_TIME" ]; then
    NEW_FILES=$(find /home/ga -maxdepth 3 -type f \( -name "*.xls" -o -name "*.tbl" -o -name "*.csv" \) -newer "$BASELINE_TIME" 2>/dev/null)
    if [ -n "$NEW_FILES" ]; then
        echo "New files since task start:"
        echo "$NEW_FILES"
        MEASUREMENT_FILES_FOUND="$MEASUREMENT_FILES_FOUND $NEW_FILES"
        if [ -z "$MEASUREMENT_FILE" ]; then
            MEASUREMENT_FILE=$(echo "$NEW_FILES" | head -1)
        fi
    fi
fi

# ============================================================
# Parse measurement file
# ============================================================
NUM_DATA_ROWS=0
NUM_STARS_MEASURED=0
HAS_TIME_COL="false"
HAS_FLUX_COL="false"
NUM_APERTURES=0
NUM_COMPARISON_STARS=0

if [ -n "$MEASUREMENT_FILE" ] && [ -f "$MEASUREMENT_FILE" ]; then
    echo ""
    echo "=== Parsing measurement file: $MEASUREMENT_FILE ==="

    NUM_DATA_ROWS=$(wc -l < "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    NUM_DATA_ROWS=$((NUM_DATA_ROWS - 1))
    if [ "$NUM_DATA_ROWS" -lt 0 ]; then NUM_DATA_ROWS=0; fi
    echo "Number of data rows: $NUM_DATA_ROWS"

    HEADER=$(head -1 "$MEASUREMENT_FILE" 2>/dev/null || echo "")

    if echo "$HEADER" | grep -qiE "J\.D\.|JD|BJD"; then
        HAS_TIME_COL="true"
        echo "Time column found"
    fi

    if echo "$HEADER" | grep -qiE "rel_flux|Source-Sky|tot_C_cnts"; then
        HAS_FLUX_COL="true"
        echo "Flux column found"
    fi

    # Count apertures (T1, C2, C3, etc. in column names)
    NUM_APERTURES=$(echo "$HEADER" | grep -oE "rel_flux_[TC][0-9]+" | wc -l || echo "0")
    NUM_COMPARISON_STARS=$(echo "$HEADER" | grep -oE "rel_flux_C[0-9]+" | wc -l || echo "0")
    NUM_STARS_MEASURED=$NUM_APERTURES
    echo "Apertures: $NUM_APERTURES, Comparison stars: $NUM_COMPARISON_STARS"
fi

# ============================================================
# Search for report file
# ============================================================
echo ""
echo "=== Searching for report file ==="

REPORT_FILE=""
REPORT_CONTENT=""

report_patterns=(
    "$PROJECT_DIR/variable_star_report.txt"
    "$PROJECT_DIR/variable_report.txt"
)

# Check exact paths first
for rp in "${report_patterns[@]}"; do
    if [ -f "$rp" ]; then
        REPORT_FILE="$rp"
        break
    fi
done

# If not found, do a broader search
if [ -z "$REPORT_FILE" ]; then
    for dir in $SEARCH_DIRS; do
        if [ -d "$dir" ]; then
            found=$(find "$dir" -maxdepth 2 -type f \( \
                -name "*variable*report*" -o \
                -name "*report*variable*" -o \
                -name "*variable*.txt" -o \
                -name "*report*.txt" \
            \) ! -name "*.fits" 2>/dev/null | head -1)

            if [ -n "$found" ]; then
                REPORT_FILE="$found"
                break
            fi
        fi
    done
fi

REPORT_FOUND="false"
REPORTED_VARIABLE_STAR=""
REPORTED_DEPTH=""
REPORTED_TIMING=""

if [ -n "$REPORT_FILE" ] && [ -f "$REPORT_FILE" ]; then
    REPORT_FOUND="true"
    REPORT_CONTENT=$(head -c 3000 "$REPORT_FILE" 2>/dev/null || echo "")
    echo "Found report file: $REPORT_FILE"
    echo "Content preview:"
    echo "$REPORT_CONTENT" | head -20
fi

# ============================================================
# Parse report content with Python for detailed extraction
# ============================================================

python3 << 'PYEOF'
import json
import os
import re

report_file = os.environ.get('REPORT_FILE', '')
report_content = ""
if report_file and os.path.exists(report_file):
    with open(report_file, 'r', errors='replace') as f:
        report_content = f.read()[:3000]

result = {
    "report_content": report_content,
    "variable_star_identified": False,
    "variable_star_label": "",
    "variable_star_name_match": False,
    "reported_depth_value": None,
    "reported_depth_is_percent": False,
    "reported_timing_frames": [],
    "reported_timing_jd": None,
}

if not report_content:
    with open('/tmp/report_parse.json', 'w') as f:
        json.dump(result, f, indent=2)
    exit(0)

content_lower = report_content.lower()

# Check if variable star is identified as WASP-12 or T1 (target aperture label)
wasp12_patterns = [
    r'wasp[\s\-]*12',
    r'\bT1\b',
    r'target\s*(star|aperture)',
    r'star\s*#?\s*1\b',
    r'aperture\s*#?\s*1\b',
]

for pat in wasp12_patterns:
    m = re.search(pat, report_content, re.IGNORECASE)
    if m:
        result["variable_star_identified"] = True
        result["variable_star_label"] = m.group(0).strip()
        # Check if it specifically names WASP-12
        if re.search(r'wasp[\s\-]*12', m.group(0), re.IGNORECASE):
            result["variable_star_name_match"] = True
        break

# Parse transit/eclipse depth
# Look for patterns like "1.4%", "depth of 1.4", "~1.4 percent", "0.014 fraction"
depth_patterns = [
    r'depth[:\s]+~?([0-9]+\.?[0-9]*)\s*(%|percent)',
    r'(?:dip|decrease|dimming|drop)[:\s]+~?([0-9]+\.?[0-9]*)\s*(%|percent)',
    r'~?([0-9]+\.?[0-9]*)\s*(%|percent)\s*(?:dip|decrease|depth|dimming|drop)',
    r'depth[:\s]+~?([0-9]+\.?[0-9]*)\s*(fraction)?',
    r'([0-9]+\.?[0-9]*)\s*(%|percent)',
    r'0\.0[0-9]+\s*(fraction|flux)',
]

for pat in depth_patterns:
    m = re.search(pat, report_content, re.IGNORECASE)
    if m:
        try:
            val = float(m.group(1))
            # Determine if it's a percent or fraction
            unit = m.group(2) if len(m.groups()) >= 2 and m.group(2) else ""
            if unit and unit.lower() in ('%', 'percent'):
                result["reported_depth_value"] = val
                result["reported_depth_is_percent"] = True
            elif val < 0.1:
                # Likely a fraction (e.g., 0.014)
                result["reported_depth_value"] = val * 100
                result["reported_depth_is_percent"] = True
            else:
                result["reported_depth_value"] = val
                result["reported_depth_is_percent"] = True
            break
        except ValueError:
            pass

# Parse timing information
# Frame numbers
frame_match = re.findall(r'frame[s]?\s*[:#]?\s*([\d,\s\-and]+)', report_content, re.IGNORECASE)
if frame_match:
    for fm in frame_match:
        nums = re.findall(r'\d+', fm)
        result["reported_timing_frames"] = [int(n) for n in nums if 1 <= int(n) <= 200]
        if result["reported_timing_frames"]:
            break

# JD timestamps
jd_match = re.search(r'(?:JD|BJD|HJD)[:\s]*~?([0-9]{7}\.?[0-9]*)', report_content, re.IGNORECASE)
if jd_match:
    try:
        result["reported_timing_jd"] = float(jd_match.group(1))
    except ValueError:
        pass

# Also check for minimum mentions
min_match = re.search(r'minimum\s+(?:at\s+)?(?:frame\s+)?(\d+)', report_content, re.IGNORECASE)
if min_match and not result["reported_timing_frames"]:
    try:
        frame_num = int(min_match.group(1))
        if 1 <= frame_num <= 200:
            result["reported_timing_frames"] = [frame_num]
    except ValueError:
        pass

with open('/tmp/report_parse.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Variable star identified: {result['variable_star_identified']}")
print(f"Variable star label: {result['variable_star_label']}")
print(f"Name match (WASP-12): {result['variable_star_name_match']}")
print(f"Depth: {result['reported_depth_value']}")
print(f"Timing frames: {result['reported_timing_frames']}")
print(f"Timing JD: {result['reported_timing_jd']}")
PYEOF

# ============================================================
# Check for light curve plot files
# ============================================================
LIGHTCURVE_FILE=""
for dir in $SEARCH_DIRS; do
    found=$(find "$dir" -maxdepth 2 -type f \( \
        -name "*plot*.png" -o \
        -name "*curve*.png" -o \
        -name "*Multi-plot*.png" -o \
        -name "*lightcurve*.png" \
    \) 2>/dev/null | head -1)

    if [ -n "$found" ]; then
        LIGHTCURVE_FILE="$found"
        echo "Found light curve plot: $LIGHTCURVE_FILE"
        break
    fi
done

# ============================================================
# Cleanup: Close AstroImageJ
# ============================================================
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

# ============================================================
# Create final result JSON
# ============================================================
MEASUREMENT_FILES_STR=$(echo "$MEASUREMENT_FILES_FOUND" | tr ' \n' '|' | sed 's/|$//')

# Read parsed report data
REPORT_PARSE="/tmp/report_parse.json"
VAR_IDENTIFIED="false"
VAR_LABEL=""
VAR_NAME_MATCH="false"
DEPTH_VAL=""
TIMING_FRAMES="[]"
TIMING_JD=""
PARSED_REPORT_CONTENT=""

if [ -f "$REPORT_PARSE" ]; then
    VAR_IDENTIFIED=$(python3 -c "import json; print(str(json.load(open('$REPORT_PARSE')).get('variable_star_identified', False)).lower())" 2>/dev/null || echo "false")
    VAR_LABEL=$(python3 -c "import json; print(json.load(open('$REPORT_PARSE')).get('variable_star_label', ''))" 2>/dev/null || echo "")
    VAR_NAME_MATCH=$(python3 -c "import json; print(str(json.load(open('$REPORT_PARSE')).get('variable_star_name_match', False)).lower())" 2>/dev/null || echo "false")
    DEPTH_VAL=$(python3 -c "import json; v=json.load(open('$REPORT_PARSE')).get('reported_depth_value'); print(v if v is not None else '')" 2>/dev/null || echo "")
    TIMING_FRAMES=$(python3 -c "import json; print(json.dumps(json.load(open('$REPORT_PARSE')).get('reported_timing_frames', [])))" 2>/dev/null || echo "[]")
    TIMING_JD=$(python3 -c "import json; v=json.load(open('$REPORT_PARSE')).get('reported_timing_jd'); print(v if v is not None else '')" 2>/dev/null || echo "")
    PARSED_REPORT_CONTENT=$(python3 -c "import json; print(json.load(open('$REPORT_PARSE')).get('report_content', '')[:2000])" 2>/dev/null || echo "")
fi

cat > /tmp/task_result.json << EOF
{
    "measurement_file_found": $([ -n "$MEASUREMENT_FILE" ] && echo "true" || echo "false"),
    "measurement_file_path": "$MEASUREMENT_FILE",
    "num_data_rows": $NUM_DATA_ROWS,
    "num_stars_measured": $NUM_STARS_MEASURED,
    "num_apertures": $NUM_APERTURES,
    "num_comparison_stars": $NUM_COMPARISON_STARS,
    "has_time_column": $HAS_TIME_COL,
    "has_flux_column": $HAS_FLUX_COL,
    "report_file_found": $REPORT_FOUND,
    "report_file_path": "$REPORT_FILE",
    "report_content": $(python3 -c "import json; print(json.dumps('$PARSED_REPORT_CONTENT'[:2000]))" 2>/dev/null || echo '""'),
    "variable_star_identified": $VAR_IDENTIFIED,
    "variable_star_label": "$VAR_LABEL",
    "variable_star_name_match": $VAR_NAME_MATCH,
    "reported_depth_percent": "$DEPTH_VAL",
    "reported_timing_frames": $TIMING_FRAMES,
    "reported_timing_jd": "$TIMING_JD",
    "lightcurve_window_found": $LIGHTCURVE_WINDOW,
    "lightcurve_file": "$LIGHTCURVE_FILE",
    "multiap_window_found": $MULTIAP_WINDOW,
    "screenshot_path": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|')",
    "measurement_files_searched": "$MEASUREMENT_FILES_STR",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
