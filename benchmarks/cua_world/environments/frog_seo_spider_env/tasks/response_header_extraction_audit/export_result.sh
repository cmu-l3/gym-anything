#!/bin/bash
# Export script for Response Header Extraction Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Response Header Extraction Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Expected file paths
EXPECTED_CSV="$EXPORT_DIR/header_audit.csv"
EXPECTED_REPORT="$REPORTS_DIR/server_fingerprint.txt"

# Search for the CSV file (allow flexibility in naming if created recently)
FOUND_CSV=""
if [ -f "$EXPECTED_CSV" ]; then
    FOUND_CSV="$EXPECTED_CSV"
else
    # Look for any recent CSV that might contain the data
    FOUND_CSV=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f -print -quit 2>/dev/null)
fi

# Search for the report file
FOUND_REPORT=""
if [ -f "$EXPECTED_REPORT" ]; then
    FOUND_REPORT="$EXPECTED_REPORT"
else
    # Look for any text file in reports dir
    FOUND_REPORT=$(find "$REPORTS_DIR" -name "*.txt" -newer /tmp/task_start_time -type f -print -quit 2>/dev/null)
fi

# Analyze CSV content using Python
CSV_ANALYSIS=$(python3 << PYEOF
import csv
import json
import os

csv_path = "$FOUND_CSV"
result = {
    "csv_found": False,
    "row_count": 0,
    "has_server_header": False,
    "has_mime_type": False,
    "has_date_header": False,
    "target_domain_found": False,
    "extracted_server_value": "",
    "unique_mime_types": 0
}

if csv_path and os.path.exists(csv_path):
    result["csv_found"] = True
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            reader = csv.reader(f)
            headers = next(reader, [])
            rows = list(reader)
            result["row_count"] = len(rows)
            
            # Normalize headers for checking
            norm_headers = [h.lower().replace(' ', '_').replace('1', '').strip() for h in headers]
            
            # Check for requested columns (allowing some variation)
            result["has_server_header"] = any("server" in h for h in norm_headers)
            result["has_mime_type"] = any("mime" in h or "content_type" in h or "content-type" in h for h in norm_headers)
            result["has_date_header"] = any("response_date" in h or "date" in h for h in norm_headers)
            
            # Check content
            if rows:
                # Check for target domain in first column (usually Address)
                if "crawler-test.com" in rows[0][0]:
                    result["target_domain_found"] = True
                
                # Try to extract server value if column exists
                server_indices = [i for i, h in enumerate(norm_headers) if "server" in h]
                if server_indices:
                    idx = server_indices[0]
                    # Get first non-empty value
                    for r in rows:
                        if len(r) > idx and r[idx].strip():
                            result["extracted_server_value"] = r[idx].strip()
                            break
                
                # Count unique mime types if column exists
                mime_indices = [i for i, h in enumerate(norm_headers) if "mime" in h or "content_type" in h]
                if mime_indices:
                    idx = mime_indices[0]
                    types = set()
                    for r in rows:
                        if len(r) > idx and r[idx].strip():
                            types.add(r[idx].strip())
                    result["unique_mime_types"] = len(types)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# Analyze Report content
REPORT_ANALYSIS=$(python3 << PYEOF
import json
import os

report_path = "$FOUND_REPORT"
result = {
    "report_found": False,
    "size_bytes": 0,
    "content_valid": False,
    "mentions_server": False
}

if report_path and os.path.exists(report_path):
    result["report_found"] = True
    result["size_bytes"] = os.path.getsize(report_path)
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().lower()
            if len(content) > 10:
                result["content_valid"] = True
            
            # Check for keywords
            if "nginx" in content or "apache" in content or "server" in content:
                result["mentions_server"] = True
    except:
        pass

print(json.dumps(result))
PYEOF
)

# Check if SF is running
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Combine everything into final JSON
python3 << PYEOF
import json

csv_data = json.loads('''$CSV_ANALYSIS''')
report_data = json.loads('''$REPORT_ANALYSIS''')

final_result = {
    "sf_running": $SF_RUNNING,
    "timestamp": "$(date -Iseconds)",
    "csv_data": csv_data,
    "report_data": report_data,
    "found_csv_path": "$FOUND_CSV",
    "found_report_path": "$FOUND_REPORT"
}

with open('/tmp/response_header_extraction_audit_result.json', 'w') as f:
    json.dump(final_result, f, indent=2)

print("Result saved to /tmp/response_header_extraction_audit_result.json")
PYEOF

cat /tmp/response_header_extraction_audit_result.json
echo "=== Export Complete ==="