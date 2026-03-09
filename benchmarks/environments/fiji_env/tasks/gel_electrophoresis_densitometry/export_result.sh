#!/bin/bash
echo "=== Exporting Gel Electrophoresis Densitometry Results ==="

# Read task start timestamp
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
echo "Task start timestamp: $TASK_START"

# Take final screenshot for evidence
DISPLAY=:1 scrot /tmp/fiji_gel_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/fiji_gel_final.png 2>/dev/null || true
echo "Final screenshot saved"

# Initialize result variables with defaults
CSV_EXISTS="false"
CSV_MTIME=0
CSV_MODIFIED_AFTER_START="false"
N_LANES=0
HAS_REQUIRED_COLUMNS="false"
RAW_INTENSITIES_JSON="[]"
NORMALIZED_INTENSITIES_JSON="[]"
RAW_INTENSITIES_POSITIVE="false"
NORMALIZED_HAS_VARIATION="false"
LANE1_NORMALIZED_NEAR_ONE="false"

PROFILES_EXISTS="false"
PROFILES_MTIME=0
PROFILES_MODIFIED_AFTER_START="false"
PROFILES_SIZE=0

REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_MODIFIED_AFTER_START="false"
REPORT_SIZE=0
REPORT_HAS_LANE="false"
REPORT_HAS_INTENSITY="false"

CSV_PATH="/home/ga/Fiji_Data/results/gel/band_quantification.csv"
PROFILES_PATH="/home/ga/Fiji_Data/results/gel/lane_profiles.png"
REPORT_PATH="/home/ga/Fiji_Data/results/gel/densitometry_report.txt"

# Check CSV file
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(python3 -c "import os; print(int(os.path.getmtime('$CSV_PATH')))" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        CSV_MODIFIED_AFTER_START="true"
    fi
    echo "CSV found: $CSV_PATH (mtime=$CSV_MTIME, start=$TASK_START)"
fi

# Check profiles PNG
if [ -f "$PROFILES_PATH" ]; then
    PROFILES_EXISTS="true"
    PROFILES_MTIME=$(python3 -c "import os; print(int(os.path.getmtime('$PROFILES_PATH')))" 2>/dev/null || echo "0")
    PROFILES_SIZE=$(stat -c%s "$PROFILES_PATH" 2>/dev/null || echo "0")
    if [ "$PROFILES_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        PROFILES_MODIFIED_AFTER_START="true"
    fi
    echo "Profiles PNG found: size=${PROFILES_SIZE} bytes (mtime=$PROFILES_MTIME)"
fi

# Check report TXT
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(python3 -c "import os; print(int(os.path.getmtime('$REPORT_PATH')))" 2>/dev/null || echo "0")
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_MODIFIED_AFTER_START="true"
    fi
    # Check for required keywords (case-insensitive)
    if grep -qi "lane" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_LANE="true"
    fi
    if grep -qi "intensity\|expression\|signal\|absorbance" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_INTENSITY="true"
    fi
    echo "Report found: size=${REPORT_SIZE} bytes (mtime=$REPORT_MTIME)"
    echo "  has_lane=${REPORT_HAS_LANE} has_intensity=${REPORT_HAS_INTENSITY}"
fi

# Parse CSV with Python for robust column and data extraction
python3 << PYEOF
import json
import os
import csv
import sys

csv_path = "$CSV_PATH"
task_start = int("$TASK_START") if "$TASK_START".isdigit() else 0

# Results to populate
n_lanes = 0
has_required_columns = False
raw_intensities = []
normalized_intensities = []
raw_intensities_positive = False
normalized_has_variation = False
lane1_normalized_near_one = False

if os.path.exists(csv_path):
    try:
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            content = f.read().strip()

        if content:
            # Try CSV parsing
            lines = content.splitlines()
            # Find header line
            header = []
            data_rows = []

            for i, line in enumerate(lines):
                # Skip comment lines
                if line.strip().startswith('#'):
                    continue
                parts = [p.strip() for p in line.split(',')]
                if not header:
                    header = [h.lower() for h in parts]
                else:
                    if any(p for p in parts):
                        data_rows.append(parts)

            # Map flexible column names to standard names
            def find_col(names, candidates):
                for name in names:
                    for c in candidates:
                        if c in name:
                            return names.index(name)
                return -1

            lane_idx = find_col(header, ['lane_id', 'lane'])
            raw_idx = find_col(header, ['raw_intensity', 'raw', 'intensity', 'area', 'peak_area'])
            norm_idx = find_col(header, ['normalized_intensity', 'normalized', 'norm', 'ratio', 'relative'])
            bg_idx = find_col(header, ['background_intensity', 'background', 'bg', 'baseline'])
            pct_idx = find_col(header, ['peak_area_percent', 'percent', 'peak_percent', 'pct'])

            # Require at minimum lane, raw, normalized columns
            if lane_idx >= 0 and raw_idx >= 0 and norm_idx >= 0:
                has_required_columns = True

            # Extract data
            for row in data_rows:
                if len(row) == 0:
                    continue
                try:
                    raw_val = float(row[raw_idx]) if raw_idx >= 0 and raw_idx < len(row) else 0.0
                    norm_val = float(row[norm_idx]) if norm_idx >= 0 and norm_idx < len(row) else 0.0
                    raw_intensities.append(raw_val)
                    normalized_intensities.append(norm_val)
                    n_lanes += 1
                except (ValueError, IndexError):
                    continue

            # Checks
            if raw_intensities:
                raw_intensities_positive = all(v > 0 for v in raw_intensities)

            if len(normalized_intensities) >= 2:
                spread = max(normalized_intensities) - min(normalized_intensities)
                normalized_has_variation = spread > 0.05

            if normalized_intensities:
                lane1_norm = normalized_intensities[0]
                lane1_normalized_near_one = abs(lane1_norm - 1.0) < 0.15

    except Exception as e:
        print(f"CSV parse error: {e}", file=sys.stderr)

# Cap list output at 10 items for JSON
raw_out = raw_intensities[:10]
norm_out = normalized_intensities[:10]

result = {
    "n_lanes": n_lanes,
    "has_required_columns": has_required_columns,
    "raw_intensities": raw_out,
    "normalized_intensities": norm_out,
    "raw_intensities_positive": raw_intensities_positive,
    "normalized_has_variation": normalized_has_variation,
    "lane1_normalized_near_one": lane1_normalized_near_one
}

# Write to a temp file that bash will read
with open('/tmp/gel_csv_analysis.json', 'w') as f:
    json.dump(result, f)

print(f"CSV analysis: n_lanes={n_lanes}, has_cols={has_required_columns}, "
      f"raw_pos={raw_intensities_positive}, norm_var={normalized_has_variation}, "
      f"lane1_near1={lane1_normalized_near_one}")
PYEOF

# Read CSV analysis results back
if [ -f /tmp/gel_csv_analysis.json ]; then
    N_LANES=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(d['n_lanes'])" 2>/dev/null || echo "0")
    HAS_REQUIRED_COLUMNS=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(str(d['has_required_columns']).lower())" 2>/dev/null || echo "false")
    RAW_INTENSITIES_JSON=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(json.dumps(d['raw_intensities']))" 2>/dev/null || echo "[]")
    NORMALIZED_INTENSITIES_JSON=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(json.dumps(d['normalized_intensities']))" 2>/dev/null || echo "[]")
    RAW_INTENSITIES_POSITIVE=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(str(d['raw_intensities_positive']).lower())" 2>/dev/null || echo "false")
    NORMALIZED_HAS_VARIATION=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(str(d['normalized_has_variation']).lower())" 2>/dev/null || echo "false")
    LANE1_NORMALIZED_NEAR_ONE=$(python3 -c "import json; d=json.load(open('/tmp/gel_csv_analysis.json')); print(str(d['lane1_normalized_near_one']).lower())" 2>/dev/null || echo "false")
fi

echo "Summary:"
echo "  CSV: exists=${CSV_EXISTS}, modified_after_start=${CSV_MODIFIED_AFTER_START}, n_lanes=${N_LANES}"
echo "  Columns OK: ${HAS_REQUIRED_COLUMNS}"
echo "  Raw intensities: ${RAW_INTENSITIES_JSON}"
echo "  Normalized intensities: ${NORMALIZED_INTENSITIES_JSON}"
echo "  Raw all positive: ${RAW_INTENSITIES_POSITIVE}"
echo "  Normalized has variation: ${NORMALIZED_HAS_VARIATION}"
echo "  Lane1 norm near 1.0: ${LANE1_NORMALIZED_NEAR_ONE}"
echo "  Profiles PNG: exists=${PROFILES_EXISTS}, size=${PROFILES_SIZE}, modified=${PROFILES_MODIFIED_AFTER_START}"
echo "  Report TXT: exists=${REPORT_EXISTS}, size=${REPORT_SIZE}, modified=${REPORT_MODIFIED_AFTER_START}"

# Write final result JSON using Python for robust serialization
python3 << PYEOF
import json
import os

def b(s):
    """Convert shell boolean string to Python bool."""
    return str(s).strip().lower() in ('true', '1', 'yes')

result = {
    "task_start": int("$TASK_START") if "$TASK_START".isdigit() else 0,
    "csv_exists": b("$CSV_EXISTS"),
    "csv_modified_after_start": b("$CSV_MODIFIED_AFTER_START"),
    "n_lanes": int("$N_LANES") if "$N_LANES".isdigit() else 0,
    "has_required_columns": b("$HAS_REQUIRED_COLUMNS"),
    "raw_intensities": $RAW_INTENSITIES_JSON,
    "normalized_intensities": $NORMALIZED_INTENSITIES_JSON,
    "raw_intensities_positive": b("$RAW_INTENSITIES_POSITIVE"),
    "normalized_has_variation": b("$NORMALIZED_HAS_VARIATION"),
    "lane1_normalized_near_one": b("$LANE1_NORMALIZED_NEAR_ONE"),
    "profiles_exists": b("$PROFILES_EXISTS"),
    "profiles_modified_after_start": b("$PROFILES_MODIFIED_AFTER_START"),
    "profiles_size_bytes": int("$PROFILES_SIZE") if "$PROFILES_SIZE".isdigit() else 0,
    "report_exists": b("$REPORT_EXISTS"),
    "report_modified_after_start": b("$REPORT_MODIFIED_AFTER_START"),
    "report_size_bytes": int("$REPORT_SIZE") if "$REPORT_SIZE".isdigit() else 0,
    "report_has_lane_keyword": b("$REPORT_HAS_LANE"),
    "report_has_intensity_keyword": b("$REPORT_HAS_INTENSITY"),
}

out_path = '/tmp/gel_result.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)

os.chmod(out_path, 0o666)
print(f"Result JSON written to {out_path}")
print(json.dumps(result, indent=2))
PYEOF

if [ ! -f /tmp/gel_result.json ]; then
    echo "WARNING: Python JSON write failed, writing fallback JSON"
    cat > /tmp/gel_result.json << JSONEOF
{
  "task_start": $TASK_START,
  "csv_exists": $CSV_EXISTS,
  "csv_modified_after_start": $CSV_MODIFIED_AFTER_START,
  "n_lanes": $N_LANES,
  "has_required_columns": $HAS_REQUIRED_COLUMNS,
  "raw_intensities": [],
  "normalized_intensities": [],
  "raw_intensities_positive": $RAW_INTENSITIES_POSITIVE,
  "normalized_has_variation": $NORMALIZED_HAS_VARIATION,
  "lane1_normalized_near_one": $LANE1_NORMALIZED_NEAR_ONE,
  "profiles_exists": $PROFILES_EXISTS,
  "profiles_modified_after_start": $PROFILES_MODIFIED_AFTER_START,
  "profiles_size_bytes": $PROFILES_SIZE,
  "report_exists": $REPORT_EXISTS,
  "report_modified_after_start": $REPORT_MODIFIED_AFTER_START,
  "report_size_bytes": $REPORT_SIZE,
  "report_has_lane_keyword": $REPORT_HAS_LANE,
  "report_has_intensity_keyword": $REPORT_HAS_INTENSITY
}
JSONEOF
    chmod 666 /tmp/gel_result.json
fi

echo "=== Export Complete ==="
