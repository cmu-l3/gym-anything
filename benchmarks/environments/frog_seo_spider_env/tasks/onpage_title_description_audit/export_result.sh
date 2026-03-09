#!/bin/bash
# Export script for On-Page Title & Description Audit

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting On-Page Audit Result ==="

take_screenshot /tmp/task_final.png

# Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_FILE="/home/ga/Documents/SEO/reports/onpage_audit_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
SF_RUNNING="false"
TITLES_CSV_PATH=""
DESCRIPTIONS_CSV_PATH=""
TITLES_CSV_VALID="false"
DESCRIPTIONS_CSV_VALID="false"
TITLES_ROW_COUNT=0
DESCRIPTIONS_ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_KEYWORDS="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Helper to check file validity (modified after start, contains domain, has rows)
check_csv_validity() {
    local file="$1"
    local type="$2" # "title" or "description"
    
    # Check timestamp
    local mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    if [ "$mtime" -le "$TASK_START_EPOCH" ]; then
        return 1
    fi
    
    # Check for domain (content validation)
    if ! grep -qi "books.toscrape.com" "$file" 2>/dev/null; then
        return 1
    fi
    
    # Check column headers based on type
    local header=$(head -1 "$file" 2>/dev/null || echo "")
    if [ "$type" == "title" ]; then
        if ! echo "$header" | grep -qi "Title 1"; then
            return 1
        fi
    elif [ "$type" == "description" ]; then
        if ! echo "$header" | grep -qi "Meta Description 1\|Description 1"; then
            return 1
        fi
    fi
    
    return 0
}

# Scan Export Directory for relevant files
if [ -d "$EXPORT_DIR" ]; then
    # Look for Titles CSV
    while IFS= read -r -d '' f; do
        if [[ "$(basename "$f")" =~ title ]] || [[ "$(basename "$f")" =~ Title ]]; then
            if check_csv_validity "$f" "title"; then
                TITLES_CSV_PATH="$f"
                TITLES_CSV_VALID="true"
                TITLES_ROW_COUNT=$(($(wc -l < "$f") - 1))
                break # Use the first valid one found
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*title*.csv" -type f -print0 2>/dev/null)
    
    # Look for Descriptions CSV
    while IFS= read -r -d '' f; do
        if [[ "$(basename "$f")" =~ description ]] || [[ "$(basename "$f")" =~ Description ]]; then
            if check_csv_validity "$f" "description"; then
                DESCRIPTIONS_CSV_PATH="$f"
                DESCRIPTIONS_CSV_VALID="true"
                DESCRIPTIONS_ROW_COUNT=$(($(wc -l < "$f") - 1))
                break
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*description*.csv" -type f -print0 2>/dev/null)
fi

# Check Report File
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE")
    
    # Check content
    CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    
    # Check for numbers (digits)
    if [[ "$CONTENT" =~ [0-9] ]]; then
        REPORT_HAS_NUMBERS="true"
    fi
    
    # Check for keywords
    if [[ "$CONTENT" =~ title ]] && [[ "$CONTENT" =~ description ]]; then
        REPORT_HAS_KEYWORDS="true"
    fi
fi

# Create result JSON using Python
python3 << PYEOF
import json
import os

result = {
    "sf_running": $SF_RUNNING,
    "titles_csv_path": "$TITLES_CSV_PATH",
    "titles_csv_valid": $TITLES_CSV_VALID,
    "titles_row_count": $TITLES_ROW_COUNT,
    "descriptions_csv_path": "$DESCRIPTIONS_CSV_PATH",
    "descriptions_csv_valid": $DESCRIPTIONS_CSV_VALID,
    "descriptions_row_count": $DESCRIPTIONS_ROW_COUNT,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_has_numbers": $REPORT_HAS_NUMBERS,
    "report_has_keywords": $REPORT_HAS_KEYWORDS,
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="