#!/bin/bash
echo "=== Exporting Multi-Channel Cell Pipeline Result ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Define paths
RESULTS_DIR="/home/ga/Fiji_Data/results/cell_pipeline"
CSV_PATH="$RESULTS_DIR/channel_measurements.csv"
FIGURE_PATH="$RESULTS_DIR/analysis_figure.png"
REPORT_PATH="$RESULTS_DIR/analysis_report.txt"
JSON_OUTPUT="/tmp/multichannel_pipeline_result.json"

# Use Python to parse results and collect evidence
python3 << PYEOF
import json
import os
import csv
import re

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": False,
    "csv_modified": False,
    "csv_rows": 0,
    "csv_cols": [],
    "csv_metrics": {},
    "figure_exists": False,
    "figure_modified": False,
    "figure_size": 0,
    "report_exists": False,
    "report_modified": False,
    "report_content": "",
    "report_has_metrics": False,
    "app_running": False
}

# 1. Check CSV
if os.path.exists("$CSV_PATH"):
    result["csv_exists"] = True
    if os.path.getmtime("$CSV_PATH") > $TASK_START:
        result["csv_modified"] = True

    try:
        with open("$CSV_PATH", 'r') as f:
            reader = csv.DictReader(f)
            if reader.fieldnames:
                result["csv_cols"] = [c.strip().lower() for c in reader.fieldnames]

                rows = list(reader)
                result["csv_rows"] = len(rows)

                # Extract metric name -> value pairs
                # Expected format: Channel, Metric_Name, Value
                # But be flexible with column naming
                metrics = {}
                for row in rows:
                    name = None
                    value = None
                    for k, v in row.items():
                        kl = k.strip().lower()
                        if "metric" in kl or "name" in kl:
                            name = v.strip().lower() if v else None
                        if "value" in kl:
                            try:
                                value = float(v)
                            except (ValueError, TypeError):
                                pass
                    if name and value is not None:
                        metrics[name] = value

                # Fallback: if CSV uses non-standard layout (e.g., metric as rows
                # with columns like Metric, Value without Channel), try simpler parse
                if not metrics and len(rows) > 0:
                    # Try first two columns as name, value
                    for row in rows:
                        vals = list(row.values())
                        if len(vals) >= 2:
                            try:
                                name_candidate = str(vals[0]).strip().lower() if len(vals) > 1 else None
                                val_candidate = None
                                for v in vals[1:]:
                                    try:
                                        val_candidate = float(v)
                                        break
                                    except (ValueError, TypeError):
                                        continue
                                if name_candidate and val_candidate is not None:
                                    metrics[name_candidate] = val_candidate
                            except:
                                pass

                result["csv_metrics"] = metrics
    except Exception as e:
        result["csv_error"] = str(e)

# 2. Check Figure
if os.path.exists("$FIGURE_PATH"):
    result["figure_exists"] = True
    result["figure_size"] = os.path.getsize("$FIGURE_PATH")
    if os.path.getmtime("$FIGURE_PATH") > $TASK_START:
        result["figure_modified"] = True

# 3. Check Report
if os.path.exists("$REPORT_PATH"):
    result["report_exists"] = True
    if os.path.getmtime("$REPORT_PATH") > $TASK_START:
        result["report_modified"] = True

    try:
        with open("$REPORT_PATH", 'r') as f:
            content = f.read()
            result["report_content"] = content[:2000]  # Cap at 2000 chars

            # Check for key metric keywords alongside numbers
            keywords = ["nuclear", "nuclei", "cell", "branch", "junction",
                        "actin", "feature", "area", "skeleton", "count"]
            found = sum(1 for kw in keywords if kw in content.lower())
            # Also check there are actual numbers in the report
            has_numbers = bool(re.search(r'\d+\.?\d*', content))
            result["report_has_metrics"] = (found >= 3) and has_numbers
    except Exception as e:
        result["report_error"] = str(e)

with open("$JSON_OUTPUT", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Copy output files to /tmp for verifier access
cp "$FIGURE_PATH" /tmp/verify_analysis_figure.png 2>/dev/null || true
cp "$CSV_PATH" /tmp/verify_channel_measurements.csv 2>/dev/null || true
cp "$REPORT_PATH" /tmp/verify_analysis_report.txt 2>/dev/null || true

# Check if Fiji is still running
if pgrep -f "fiji" >/dev/null || pgrep -f "ImageJ" >/dev/null; then
    python3 -c "
import json
d = json.load(open('$JSON_OUTPUT'))
d['app_running'] = True
json.dump(d, open('$JSON_OUTPUT', 'w'))
"
fi

echo "Results exported to $JSON_OUTPUT"
chmod 666 "$JSON_OUTPUT"
cat "$JSON_OUTPUT"
