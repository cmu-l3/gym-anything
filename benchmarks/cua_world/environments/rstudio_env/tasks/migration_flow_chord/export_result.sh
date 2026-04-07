#!/bin/bash
echo "=== Exporting migration_flow_chord result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
take_screenshot /tmp/task_final_screenshot.png

# Path variables
NET_CSV="/home/ga/RProjects/output/net_migration_summary.csv"
MAT_CSV="/home/ga/RProjects/output/migration_matrix.csv"
PLOT_PNG="/home/ga/RProjects/output/migration_chord.png"
SCRIPT="/home/ga/RProjects/migration_analysis.R"

# Use a Python script to robustly extract properties of the files created by the agent
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 << PYEOF
import json, os, csv

task_start = int($TASK_START)
result = {
    "task_start": task_start,
    "net_csv": {"exists": False, "is_new": False, "has_net_col": False, "row_count": 0},
    "mat_csv": {"exists": False, "is_new": False, "row_count": 0, "filtered": False},
    "plot_png": {"exists": False, "is_new": False, "size_kb": 0},
    "script": {"exists": False, "is_new": False, "has_chordDiagram": False, "has_df_m0510": False}
}

# Check Net Migration CSV
net_csv = "$NET_CSV"
if os.path.exists(net_csv):
    result["net_csv"]["exists"] = True
    if os.path.getmtime(net_csv) > task_start:
        result["net_csv"]["is_new"] = True
    try:
        with open(net_csv, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            header = next(reader, [])
            header_lower = [h.lower() for h in header]
            if any('net' in h for h in header_lower):
                result["net_csv"]["has_net_col"] = True
            rows = list(reader)
            result["net_csv"]["row_count"] = len(rows)
    except Exception:
        pass

# Check Matrix/Filtered CSV
mat_csv = "$MAT_CSV"
if os.path.exists(mat_csv):
    result["mat_csv"]["exists"] = True
    if os.path.getmtime(mat_csv) > task_start:
        result["mat_csv"]["is_new"] = True
    try:
        with open(mat_csv, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            rows = list(reader)
            result["mat_csv"]["row_count"] = max(0, len(rows) - 1)
            # Rough check for filtered logic: Should be significantly smaller than original 196x196 matrix
            # A filtered df_m0510 (>50k) usually has ~30-50 rows depending on aggregation
            if 5 < len(rows) < 150:
                result["mat_csv"]["filtered"] = True
    except Exception:
        pass

# Check Plot PNG
plot_png = "$PLOT_PNG"
if os.path.exists(plot_png):
    result["plot_png"]["exists"] = True
    if os.path.getmtime(plot_png) > task_start:
        result["plot_png"]["is_new"] = True
    result["plot_png"]["size_kb"] = os.path.getsize(plot_png) / 1024.0

# Check Script
script_path = "$SCRIPT"
if os.path.exists(script_path):
    result["script"]["exists"] = True
    if os.path.getmtime(script_path) > task_start:
        result["script"]["is_new"] = True
    try:
        with open(script_path, 'r', encoding='utf-8') as f:
            content = f.read()
            if "chordDiagram" in content:
                result["script"]["has_chordDiagram"] = True
            if "df_m0510" in content:
                result["script"]["has_df_m0510"] = True
    except Exception:
        pass

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Copy JSON to final destination and set permissions
rm -f /tmp/migration_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/migration_task_result.json
chmod 666 /tmp/migration_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/migration_task_result.json"
cat /tmp/migration_task_result.json
echo "=== Export complete ==="