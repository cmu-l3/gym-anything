#!/bin/bash
# Export script for Structured Data Schema Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Structured Data Audit Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Initialize result variables
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/structured_data_audit.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

STRUCTURED_DATA_CSV=""
INTERNAL_HTML_CSV=""
STRUCTURED_DATA_ROWS=0
INTERNAL_HTML_ROWS=0
TARGET_DOMAIN_FOUND="false"
HAS_JSONLD_COL="false"
HAS_MICRODATA_COL="false"
HAS_RDFA_COL="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT_VALID="false"
SF_RUNNING="false"

# 3. Check if Screaming Frog is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 4. Analyze CSV exports
# We look for files created/modified AFTER task start
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Only check files modified after task start
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Read header and sample lines
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            # Read first 10 lines for content checking
            SAMPLE=$(head -10 "$csv_file" 2>/dev/null || echo "")
            
            # Count data rows (total lines - 1 header)
            TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "0")
            ROW_COUNT=$((TOTAL_LINES - 1))
            if [ "$ROW_COUNT" -lt 0 ]; then ROW_COUNT=0; fi

            # Check if this is the Structured Data export
            # Identifiers: "JSON-LD", "Microdata", "RDFa", "Schema Type", "Validation" in header
            # OR filename contains "structured_data"
            IS_STRUCT_CSV="false"
            if echo "$HEADER" | grep -qi "JSON-LD\|Microdata\|RDFa\|Schema Type\|Validation"; then
                IS_STRUCT_CSV="true"
            elif echo "$csv_file" | grep -qi "structured"; then
                IS_STRUCT_CSV="true"
            fi

            if [ "$IS_STRUCT_CSV" = "true" ]; then
                STRUCTURED_DATA_CSV="$csv_file"
                STRUCTURED_DATA_ROWS="$ROW_COUNT"
                
                # Check specific columns
                if echo "$HEADER" | grep -qi "JSON-LD"; then HAS_JSONLD_COL="true"; fi
                if echo "$HEADER" | grep -qi "Microdata"; then HAS_MICRODATA_COL="true"; fi
                if echo "$HEADER" | grep -qi "RDFa"; then HAS_RDFA_COL="true"; fi
                
                # Check for target domain
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_FOUND="true"
                fi
            fi

            # Check if this is the Internal HTML export
            # Identifiers: "Title 1", "Meta Description 1", "H1-1", "Status Code"
            IS_INTERNAL_CSV="false"
            if echo "$HEADER" | grep -qi "Title 1\|Meta Description 1\|H1-1"; then
                IS_INTERNAL_CSV="true"
            elif echo "$csv_file" | grep -qi "internal_html\|internal_all"; then
                IS_INTERNAL_CSV="true"
            fi

            if [ "$IS_INTERNAL_CSV" = "true" ]; then
                INTERNAL_HTML_CSV="$csv_file"
                INTERNAL_HTML_ROWS="$ROW_COUNT"
                
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_FOUND="true"
                fi
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 5. Analyze Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check for keywords in report
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
    KEYWORDS_FOUND=0
    
    if echo "$REPORT_CONTENT" | grep -q "structured data"; then KEYWORDS_FOUND=$((KEYWORDS_FOUND+1)); fi
    if echo "$REPORT_CONTENT" | grep -qE "json-ld|microdata|rdfa|schema"; then KEYWORDS_FOUND=$((KEYWORDS_FOUND+1)); fi
    if echo "$REPORT_CONTENT" | grep -qE "product|breadcrumb|organization"; then KEYWORDS_FOUND=$((KEYWORDS_FOUND+1)); fi
    if echo "$REPORT_CONTENT" | grep -qE "missing|recommend|implement"; then KEYWORDS_FOUND=$((KEYWORDS_FOUND+1)); fi
    
    # Needs at least 2 categories of keywords to be valid
    if [ "$KEYWORDS_FOUND" -ge 2 ]; then
        REPORT_CONTENT_VALID="true"
    fi
fi

# 6. Capture Window Info (for debug/VLM correlation)
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 7. Create Result JSON
# Use Python to avoid JSON syntax errors with variable content
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "structured_data_csv_found": len("$STRUCTURED_DATA_CSV") > 0,
    "structured_data_csv_path": "$STRUCTURED_DATA_CSV",
    "structured_data_rows": $STRUCTURED_DATA_ROWS,
    "has_jsonld_col": "$HAS_JSONLD_COL" == "true",
    "has_microdata_col": "$HAS_MICRODATA_COL" == "true",
    "internal_html_csv_found": len("$INTERNAL_HTML_CSV") > 0,
    "internal_html_csv_path": "$INTERNAL_HTML_CSV",
    "internal_html_rows": $INTERNAL_HTML_ROWS,
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_content_valid": "$REPORT_CONTENT_VALID" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result saved to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="