#!/bin/bash
# Export script for Social Metadata Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Social Metadata Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
TARGET_CSV="$EXPORT_DIR/social_tags_export.csv"
REPORT_FILE="$REPORTS_DIR/missing_social_tags.txt"

# Initialize verification vars
CSV_EXISTS="false"
REPORT_EXISTS="false"
SF_RUNNING="false"
CUSTOM_COLS_FOUND=0
HAS_CRAWLER_TEST_URLS="false"
HAS_EXTRACTED_DATA="false"
VALID_ROWS=0
WINDOW_INFO=""

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Analyze CSV using Python for robust parsing
python3 << PYEOF
import csv
import json
import os
import sys

csv_path = "$TARGET_CSV"
report_path = "$REPORT_FILE"
task_start = $TASK_START_EPOCH

result = {
    "csv_exists": False,
    "csv_created_during_task": False,
    "report_exists": False,
    "report_created_during_task": False,
    "report_content_length": 0,
    "csv_rows": 0,
    "has_og_cols": False,
    "has_target_domain": False,
    "has_extracted_values": False,
    "og_title_col_name": None,
    "og_image_col_name": None
}

# Check Report
if os.path.exists(report_path):
    result["report_exists"] = True
    mtime = os.path.getmtime(report_path)
    if mtime > task_start:
        result["report_created_during_task"] = True
    
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            result["report_content_length"] = len(content)
    except:
        pass

# Check CSV
if os.path.exists(csv_path):
    result["csv_exists"] = True
    mtime = os.path.getmtime(csv_path)
    if mtime > task_start:
        result["csv_created_during_task"] = True

    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Handle potential BOM or weird encodings from SF export
            content = f.read()
            # Reset seek to start
            f.seek(0)
            
            # Basic check for domain in raw content
            if "crawler-test.com" in content:
                result["has_target_domain"] = True
            
            # Parse CSV
            reader = csv.reader(f)
            rows = list(reader)
            
            if len(rows) > 1:
                header = rows[0]
                result["csv_rows"] = len(rows) - 1
                
                # Look for custom extraction columns
                # They might be named "Custom Extraction 1", "OG Title", "Custom 1", etc.
                # We check headers first, then check data density
                possible_og_headers = [h for h in header if "custom" in h.lower() or "og" in h.lower() or "extraction" in h.lower() or "title" in h.lower() or "image" in h.lower()]
                
                # Better check: Look for extracted values in rows
                extracted_data_found = False
                og_col_indices = []
                
                # Identify potential extraction columns by index
                for i, h in enumerate(header):
                    h_lower = h.lower()
                    # Skip standard columns
                    if h_lower in ['address', 'content', 'status code', 'status', 'title 1', 'title 1 length', 'h1-1', 'meta description 1']:
                        continue
                    # Likely a custom column if it's not standard
                    og_col_indices.append(i)
                    if "og" in h_lower or "custom" in h_lower:
                        result["has_og_cols"] = True

                # Check data in those columns
                # We expect "has_og_tags" pages to have data
                # crawler-test.com/facebook/has_og_tags -> should have title "Facebook Open Graph Tags" or similar
                
                for row in rows[1:]:
                    if len(row) > 0:
                        url = row[0]
                        
                        # Check extracted values in potential custom columns
                        for idx in og_col_indices:
                            if idx < len(row) and len(row[idx].strip()) > 0:
                                val = row[idx].strip()
                                # Heuristic: OG titles/images usually look specific
                                if "http" in val or "Open Graph" in val or "Tag" in val or "og:" in val:
                                    extracted_data_found = True
                                    result["has_extracted_values"] = True
                                    
    except Exception as e:
        print(f"Error parsing CSV: {e}", file=sys.stderr)

# Output JSON
with open('/tmp/social_metadata_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Analysis complete.")
PYEOF

# Combine with shell-collected data
# We read the python output into the final JSON structure
if [ -f "/tmp/social_metadata_result.json" ]; then
    # Merge shell variables
    python3 << PYEOF
import json
with open('/tmp/social_metadata_result.json', 'r') as f:
    data = json.load(f)

data["sf_running"] = "$SF_RUNNING" == "true"
data["window_info"] = """$WINDOW_INFO"""
data["timestamp"] = "$(date -Iseconds)"

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
else
    # Fallback if python script failed
    ensure_result_file
fi

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="