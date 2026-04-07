#!/bin/bash
set -e

echo "=== Exporting protein_biochemical_profiling results ==="

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || true

# 2. Extract data using Python and save as JSON
# This ensures we don't have parsing errors with spaces/commas in the CSV
cat > /tmp/extract_results.py << 'EOF'
import csv
import json
import os

result = {
    "csv_exists": False,
    "csv_rows": [],
    "reports_count": 0,
    "ugene_stats_found": False,
    "csv_error": None
}

csv_path = "/home/ga/UGENE_Data/results/gel_calibration.csv"
if os.path.exists(csv_path):
    result["csv_exists"] = True
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize headers for the JSON export to be safe
            rows = []
            for row in reader:
                clean_row = {k.strip(): v.strip() for k, v in row.items() if k}
                rows.append(clean_row)
            result["csv_rows"] = rows
    except Exception as e:
        result["csv_error"] = str(e)

reports_dir = "/home/ga/UGENE_Data/results/reports"
if os.path.exists(reports_dir) and os.path.isdir(reports_dir):
    files = os.listdir(reports_dir)
    txt_files = [f for f in files if f.endswith('.txt') or f.endswith('.csv')]
    result["reports_count"] = len(txt_files)
    
    # Check for UGENE keywords in the reports to verify they actually exported text
    for fname in txt_files:
        try:
            with open(os.path.join(reports_dir, fname), 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().lower()
                if any(kw in content for kw in ["molecular weight", "isoelectric point", "sequence statistics", "amino acid", "mw", "pi", "daltons"]):
                    result["ugene_stats_found"] = True
                    break
        except:
            pass

# Write out to standard location
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

python3 /tmp/extract_results.py

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Extracted JSON:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="