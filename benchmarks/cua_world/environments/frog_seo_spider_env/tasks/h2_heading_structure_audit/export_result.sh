#!/bin/bash
# Export script for H2 Heading Structure Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting H2 Heading Structure Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/h2_structure_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Variables to track findings
H2_CSV_PATH=""
H2_CSV_ROWS=0
H2_CSV_HAS_DATA="false"
INTERNAL_CSV_PATH=""
INTERNAL_CSV_ROWS=0
REPORT_EXISTS="false"
REPORT_CONTENT_LENGTH=0
REPORT_HAS_NUMBERS="false"
TARGET_DOMAIN_FOUND="false"

# Check if SF is still running
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 1. Analyze CSV exports
if [ -d "$EXPORT_DIR" ]; then
    # Iterate through all CSVs in the export directory
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Only consider files created/modified after task start
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            echo "Analyzing new CSV: $csv_file"
            
            # Read header and sample data
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            # Count rows (minus header)
            ROW_COUNT=$(wc -l < "$csv_file" 2>/dev/null || echo "0")
            if [ "$ROW_COUNT" -gt 0 ]; then
                ROW_COUNT=$((ROW_COUNT - 1))
            fi

            # Check for Target Domain
            if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                TARGET_DOMAIN_FOUND="true"
            fi

            # Identify H2 CSV
            # H2 exports typically have columns: "H2-1", "H2-2", "H2 Length-1"
            if echo "$HEADER" | grep -qi "H2-1\|H2-2\|H2 Length"; then
                H2_CSV_PATH="$csv_file"
                H2_CSV_ROWS=$ROW_COUNT
                
                # Check if H2 columns actually have data (not just empty strings)
                # Look for H2 content in the file
                if grep -vE "^Address,|^Content," "$csv_file" | grep -qE ",[^,]+," 2>/dev/null; then
                    H2_CSV_HAS_DATA="true"
                fi
            fi

            # Identify Internal HTML CSV
            # Standard columns: "Title 1", "Meta Description 1", "Status Code"
            if echo "$HEADER" | grep -qi "Title 1\|Meta Description 1"; then
                INTERNAL_CSV_PATH="$csv_file"
                INTERNAL_CSV_ROWS=$ROW_COUNT
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Analyze Report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT_LENGTH=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check for quantitative data (digits)
    if grep -qE "[0-9]+" "$REPORT_PATH"; then
        REPORT_HAS_NUMBERS="true"
    fi
fi

# Write result JSON using Python for safety handling strings/booleans
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "h2_csv_path": "$H2_CSV_PATH",
    "h2_csv_exists": len("$H2_CSV_PATH") > 0,
    "h2_csv_rows": $H2_CSV_ROWS,
    "h2_csv_has_data": "$H2_CSV_HAS_DATA" == "true",
    "internal_csv_path": "$INTERNAL_CSV_PATH",
    "internal_csv_exists": len("$INTERNAL_CSV_PATH") > 0,
    "internal_csv_rows": $INTERNAL_CSV_ROWS,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_length": $REPORT_CONTENT_LENGTH,
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="