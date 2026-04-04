#!/bin/bash
# Export script for JS Rendering Content Gap Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting JS Rendering Audit Result ==="

# Capture final state
take_screenshot /tmp/task_end_screenshot.png

# Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/js_rendering_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. Analyze CSV Exports
# We are looking for a CSV created AFTER task start that contains "Rendered" columns
BEST_CSV=""
CSV_HAS_RENDERED_COLS="false"
CSV_HAS_TARGET_DOMAIN="false"
CSV_ROW_COUNT=0
GAP_DETECTED="false"

# Helper python script to analyze CSV content
ANALYZE_SCRIPT=$(cat << 'PYEOF'
import sys
import csv
import os

csv_file = sys.argv[1]
target_domain = "quotes.toscrape.com"
has_rendered = False
has_domain = False
gap_count = 0
row_count = 0

try:
    with open(csv_file, 'r', encoding='utf-8', errors='ignore') as f:
        # Read header
        header = f.readline()
        # Check for Rendered columns (e.g., "Rendered Word Count", "Rendered Title")
        if "Rendered" in header:
            has_rendered = True
        
        # Determine column indices if possible
        headers = header.strip().split(',')
        # Remove quotes if present
        headers = [h.strip('"') for h in headers]
        
        # Find indices for Word Count and Rendered Word Count
        # Note: SF CSVs can be complex, doing loose matching
        wc_idx = -1
        rwc_idx = -1
        
        for i, h in enumerate(headers):
            if h == "Word Count":
                wc_idx = i
            elif h == "Rendered Word Count":
                rwc_idx = i
        
        # Read content
        reader = csv.reader(f)
        for row in reader:
            if not row: continue
            row_count += 1
            row_str = ",".join(row)
            if target_domain in row_str:
                has_domain = True
            
            # Check content gap (Rendered > Original)
            if wc_idx != -1 and rwc_idx != -1 and len(row) > max(wc_idx, rwc_idx):
                try:
                    wc = int(row[wc_idx])
                    rwc = int(row[rwc_idx])
                    # quotes.toscrape.com/js has ~20 words raw and ~200+ rendered
                    if rwc > (wc * 2) and rwc > 50:
                        gap_count += 1
                except ValueError:
                    pass

    print(f"HAS_RENDERED={str(has_rendered).lower()}")
    print(f"HAS_DOMAIN={str(has_domain).lower()}")
    print(f"ROW_COUNT={row_count}")
    print(f"GAP_COUNT={gap_count}")

except Exception as e:
    print(f"ERROR={str(e)}")
PYEOF
)

# Find new CSVs
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            echo "Analyzing candidate CSV: $csv_file"
            
            # Run analysis
            ANALYSIS=$(python3 -c "$ANALYZE_SCRIPT" "$csv_file")
            
            # Parse results
            IS_RENDERED=$(echo "$ANALYSIS" | grep "HAS_RENDERED" | cut -d= -f2)
            IS_DOMAIN=$(echo "$ANALYSIS" | grep "HAS_DOMAIN" | cut -d= -f2)
            COUNT=$(echo "$ANALYSIS" | grep "ROW_COUNT" | cut -d= -f2)
            GAPS=$(echo "$ANALYSIS" | grep "GAP_COUNT" | cut -d= -f2)
            
            # If this is a rendered report, it's our best candidate
            if [ "$IS_RENDERED" = "true" ]; then
                BEST_CSV="$csv_file"
                CSV_HAS_RENDERED_COLS="true"
                CSV_HAS_TARGET_DOMAIN="$IS_DOMAIN"
                CSV_ROW_COUNT="$COUNT"
                if [ "$GAPS" -gt 0 ]; then
                    GAP_DETECTED="true"
                fi
                break # Found what we needed
            fi
            
            # Keep looking, but store this as fallback if it has domain
            if [ "$IS_DOMAIN" = "true" ] && [ -z "$BEST_CSV" ]; then
                BEST_CSV="$csv_file"
                CSV_HAS_TARGET_DOMAIN="true"
                CSV_ROW_COUNT="$COUNT"
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Analyze Report
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT_VALID="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_SIZE" -gt 100 ]; then
        # Check for keywords
        CONTENT=$(cat "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
        if echo "$CONTENT" | grep -qE "render|javascript|js|gap|diff|word count"; then
            REPORT_CONTENT_VALID="true"
        fi
    fi
fi

# 3. Check App Status
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 4. Generate Result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "csv_found": len("$BEST_CSV") > 0,
    "csv_path": "$BEST_CSV",
    "has_rendered_columns": "$CSV_HAS_RENDERED_COLS" == "true",
    "has_target_domain": "$CSV_HAS_TARGET_DOMAIN" == "true",
    "row_count": int("$CSV_ROW_COUNT"),
    "gap_detected": "$GAP_DETECTED" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size": int("$REPORT_SIZE"),
    "report_valid": "$REPORT_CONTENT_VALID" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Export complete. Result:")
print(json.dumps(result, indent=2))
PYEOF