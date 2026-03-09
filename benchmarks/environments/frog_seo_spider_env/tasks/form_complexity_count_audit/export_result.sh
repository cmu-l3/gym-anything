#!/bin/bash
# Export script for Form Complexity Count Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Paths
CSV_PATH="/home/ga/Documents/SEO/exports/form_complexity.csv"
REPORT_PATH="/home/ga/Documents/SEO/reports/max_inputs.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Check SF status
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get Window Info
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Analyze CSV using Python
python3 << PYEOF
import json
import csv
import os
import re

result = {
    "csv_exists": False,
    "csv_valid_format": False,
    "row_count": 0,
    "target_domain_found": False,
    "has_numeric_extraction": False,
    "extraction_column_name": None,
    "sample_values": [],
    "report_exists": False,
    "report_value": None,
    "sf_running": $SF_RUNNING,
    "window_info": """$WINDOW_INFO""",
    "timestamp": "$(date -Iseconds)"
}

csv_path = "$CSV_PATH"
report_path = "$REPORT_PATH"
task_start = $TASK_START_EPOCH

# Check CSV
if os.path.exists(csv_path):
    mtime = os.stat(csv_path).st_mtime
    if mtime > task_start:
        result["csv_exists"] = True
        try:
            with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
                # Read header
                header_line = f.readline().strip()
                headers = [h.strip() for h in next(csv.reader([header_line]))]
                
                rows = []
                for line in f:
                    rows.append(line)
                    if len(rows) > 100: break # Limit check to first 100 rows
                
                result["row_count"] = len(rows)
                
                # Check for target domain
                if "books.toscrape.com" in "".join(rows):
                    result["target_domain_found"] = True
                
                # Check for numeric extraction column
                # We look for a column that is NOT standard (Address, Status Code, etc)
                # and contains mostly small integers
                standard_cols = ['Address', 'Content', 'Status Code', 'Status', 'Indexability', 'Title 1', 'Meta Description 1', 'H1-1']
                
                # Parse sample rows to find extraction data
                if rows:
                    reader = csv.reader(rows)
                    parsed_rows = list(reader)
                    
                    if len(parsed_rows) > 0 and len(headers) > 1:
                        # Find candidate columns (those not in standard set)
                        candidate_indices = []
                        for i, h in enumerate(headers):
                            if not any(s.lower() == h.lower() for s in standard_cols) and "link" not in h.lower():
                                candidate_indices.append(i)
                        
                        # Check candidates for numeric data
                        for idx in candidate_indices:
                            is_numeric = True
                            values = []
                            for r in parsed_rows:
                                if idx < len(r):
                                    val = r[idx].strip()
                                    values.append(val)
                                    # Allow empty strings, but non-empty must be digit
                                    if val and not val.isdigit():
                                        is_numeric = False
                                        break
                            
                            # If we found a numeric column with at least some data
                            if is_numeric and any(v for v in values):
                                result["has_numeric_extraction"] = True
                                result["extraction_column_name"] = headers[idx]
                                result["sample_values"] = values[:5]
                                break

        except Exception as e:
            result["error"] = str(e)

# Check Report
if os.path.exists(report_path):
    mtime = os.stat(report_path).st_mtime
    if mtime > task_start:
        result["report_exists"] = True
        try:
            with open(report_path, 'r') as f:
                content = f.read().strip()
                # Extract first number found
                match = re.search(r'\d+', content)
                if match:
                    result["report_value"] = int(match.group())
        except Exception:
            pass

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result JSON written.")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json