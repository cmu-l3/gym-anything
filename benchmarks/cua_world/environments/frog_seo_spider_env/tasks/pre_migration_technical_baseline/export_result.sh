#!/bin/bash
# Export script for Pre-Migration Technical SEO Baseline task
# Collects file existence, sizes, timestamps, headers, and report content into result JSON.

source /workspace/scripts/task_utils.sh

echo "=== Exporting Pre-Migration Technical Baseline Result ==="

# Trap errors to ensure result JSON is always created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/migration_baseline_report.txt"

# --- Check Screaming Frog status ---
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# --- Helper: check a specific CSV file ---
# Returns pipe-delimited: exists|created_after_start|row_count|has_target_domain
check_csv_file() {
    local filepath="$1"
    local exists="false"
    local created_after_start="false"
    local row_count=0
    local has_target_domain="false"

    if [ -f "$filepath" ]; then
        exists="true"
        local file_epoch=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        if [ "$file_epoch" -gt "$TASK_START_EPOCH" ]; then
            created_after_start="true"
        fi
        local total_lines=$(wc -l < "$filepath" 2>/dev/null || echo "1")
        row_count=$((total_lines - 1))
        if [ "$row_count" -lt 0 ]; then row_count=0; fi
        if grep -qi "books.toscrape.com" "$filepath" 2>/dev/null; then
            has_target_domain="true"
        fi
    fi

    echo "${exists}|${created_after_start}|${row_count}|${has_target_domain}"
}

# --- Check each expected CSV ---
INTERNAL_INFO=$(check_csv_file "$EXPORT_DIR/baseline_internal_html.csv")
TITLES_INFO=$(check_csv_file "$EXPORT_DIR/baseline_page_titles.csv")
META_INFO=$(check_csv_file "$EXPORT_DIR/baseline_meta_descriptions.csv")
IMAGES_INFO=$(check_csv_file "$EXPORT_DIR/baseline_images.csv")
INLINKS_INFO=$(check_csv_file "$EXPORT_DIR/baseline_all_inlinks.csv")

# Parse pipe-delimited info
parse_field() { echo "$1" | cut -d'|' -f"$2"; }

INTERNAL_EXISTS=$(parse_field "$INTERNAL_INFO" 1)
INTERNAL_AFTER=$(parse_field "$INTERNAL_INFO" 2)
INTERNAL_ROWS=$(parse_field "$INTERNAL_INFO" 3)
INTERNAL_DOMAIN=$(parse_field "$INTERNAL_INFO" 4)

TITLES_EXISTS=$(parse_field "$TITLES_INFO" 1)
TITLES_AFTER=$(parse_field "$TITLES_INFO" 2)
TITLES_ROWS=$(parse_field "$TITLES_INFO" 3)
TITLES_DOMAIN=$(parse_field "$TITLES_INFO" 4)

META_EXISTS=$(parse_field "$META_INFO" 1)
META_AFTER=$(parse_field "$META_INFO" 2)
META_ROWS=$(parse_field "$META_INFO" 3)
META_DOMAIN=$(parse_field "$META_INFO" 4)

IMAGES_EXISTS=$(parse_field "$IMAGES_INFO" 1)
IMAGES_AFTER=$(parse_field "$IMAGES_INFO" 2)
IMAGES_ROWS=$(parse_field "$IMAGES_INFO" 3)
IMAGES_DOMAIN=$(parse_field "$IMAGES_INFO" 4)

INLINKS_EXISTS=$(parse_field "$INLINKS_INFO" 1)
INLINKS_AFTER=$(parse_field "$INLINKS_INFO" 2)
INLINKS_ROWS=$(parse_field "$INLINKS_INFO" 3)
INLINKS_DOMAIN=$(parse_field "$INLINKS_INFO" 4)

# --- Check CSV headers for expected columns ---
HAS_ADDRESS_COL="false"
HAS_TITLE_COL="false"
HAS_META_COL="false"
HAS_ALT_TEXT_COL="false"
HAS_SOURCE_COL="false"
HAS_DEST_COL="false"

if [ -f "$EXPORT_DIR/baseline_internal_html.csv" ]; then
    HEADER=$(head -1 "$EXPORT_DIR/baseline_internal_html.csv" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "Address"; then
        HAS_ADDRESS_COL="true"
    fi
fi

if [ -f "$EXPORT_DIR/baseline_page_titles.csv" ]; then
    HEADER=$(head -1 "$EXPORT_DIR/baseline_page_titles.csv" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "Title 1\b\|\"Title 1\""; then
        HAS_TITLE_COL="true"
    fi
fi

if [ -f "$EXPORT_DIR/baseline_meta_descriptions.csv" ]; then
    HEADER=$(head -1 "$EXPORT_DIR/baseline_meta_descriptions.csv" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "Meta Description 1\|\"Meta Description 1\""; then
        HAS_META_COL="true"
    fi
fi

if [ -f "$EXPORT_DIR/baseline_images.csv" ]; then
    HEADER=$(head -1 "$EXPORT_DIR/baseline_images.csv" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "Alt Text\|\"Alt Text\""; then
        HAS_ALT_TEXT_COL="true"
    fi
fi

if [ -f "$EXPORT_DIR/baseline_all_inlinks.csv" ]; then
    HEADER=$(head -1 "$EXPORT_DIR/baseline_all_inlinks.csv" 2>/dev/null || echo "")
    if echo "$HEADER" | grep -qi "Source"; then
        HAS_SOURCE_COL="true"
    fi
    if echo "$HEADER" | grep -qi "Destination"; then
        HAS_DEST_COL="true"
    fi
fi

# --- Check report ---
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_RECOMMENDATIONS="false"
REPORT_HAS_MIGRATION="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "")

        if echo "$REPORT_CONTENT" | grep -qE "[0-9]+"; then
            REPORT_HAS_NUMBERS="true"
        fi
        if echo "$REPORT_CONTENT" | grep -qiE "recommend|suggest|should|risk|remediat"; then
            REPORT_HAS_RECOMMENDATIONS="true"
        fi
        if echo "$REPORT_CONTENT" | grep -qiE "migrat|baseline|redesign"; then
            REPORT_HAS_MIGRATION="true"
        fi
    fi
fi

# --- Count total new CSVs ---
NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

# --- Write result JSON ---
python3 << PYEOF
import json

report_content = open("$REPORT_PATH", "r").read() if "$REPORT_EXISTS" == "true" else ""

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "new_csv_count": $NEW_CSV_COUNT,
    "internal_html": {
        "exists": "$INTERNAL_EXISTS" == "true",
        "created_after_start": "$INTERNAL_AFTER" == "true",
        "row_count": $INTERNAL_ROWS,
        "has_target_domain": "$INTERNAL_DOMAIN" == "true",
        "has_address_col": "$HAS_ADDRESS_COL" == "true"
    },
    "page_titles": {
        "exists": "$TITLES_EXISTS" == "true",
        "created_after_start": "$TITLES_AFTER" == "true",
        "row_count": $TITLES_ROWS,
        "has_target_domain": "$TITLES_DOMAIN" == "true",
        "has_title_col": "$HAS_TITLE_COL" == "true"
    },
    "meta_descriptions": {
        "exists": "$META_EXISTS" == "true",
        "created_after_start": "$META_AFTER" == "true",
        "row_count": $META_ROWS,
        "has_target_domain": "$META_DOMAIN" == "true",
        "has_meta_col": "$HAS_META_COL" == "true"
    },
    "images": {
        "exists": "$IMAGES_EXISTS" == "true",
        "created_after_start": "$IMAGES_AFTER" == "true",
        "row_count": $IMAGES_ROWS,
        "has_target_domain": "$IMAGES_DOMAIN" == "true",
        "has_alt_text_col": "$HAS_ALT_TEXT_COL" == "true"
    },
    "all_inlinks": {
        "exists": "$INLINKS_EXISTS" == "true",
        "created_after_start": "$INLINKS_AFTER" == "true",
        "row_count": $INLINKS_ROWS,
        "has_target_domain": "$INLINKS_DOMAIN" == "true",
        "has_source_col": "$HAS_SOURCE_COL" == "true",
        "has_dest_col": "$HAS_DEST_COL" == "true"
    },
    "report": {
        "exists": "$REPORT_EXISTS" == "true",
        "size_bytes": $REPORT_SIZE,
        "has_numbers": "$REPORT_HAS_NUMBERS" == "true",
        "has_recommendations": "$REPORT_HAS_RECOMMENDATIONS" == "true",
        "has_migration_context": "$REPORT_HAS_MIGRATION" == "true",
        "content": report_content
    },
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
