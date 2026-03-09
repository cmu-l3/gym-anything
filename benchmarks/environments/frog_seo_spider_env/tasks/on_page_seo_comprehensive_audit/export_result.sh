#!/bin/bash
# Export script for On-Page SEO Comprehensive Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting On-Page SEO Comprehensive Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/on_page_audit.txt"

TITLES_CSV=""
META_CSV=""
H1_CSV=""
COMPREHENSIVE_CSV=""
TITLES_ROW_COUNT=0
META_ROW_COUNT=0
H1_ROW_COUNT=0
COMPREHENSIVE_ROW_COUNT=0
HAS_TITLE_COL="false"
HAS_META_COL="false"
HAS_H1_COL="false"
TARGET_DOMAIN_IN_CSV="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_COUNTS="false"
REPORT_HAS_MULTIPLE_CATEGORIES="false"
SF_RUNNING="false"
MAX_ROW_COUNT=0

if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Find and categorize CSVs
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
            ROW_COUNT=$((TOTAL_LINES - 1))

            HAS_TITLE_THIS="false"
            HAS_META_THIS="false"
            HAS_H1_THIS="false"

            if echo "$HEADER" | grep -qi "Title 1\b\|\"Title 1\""; then
                HAS_TITLE_THIS="true"
                HAS_TITLE_COL="true"
            fi
            if echo "$HEADER" | grep -qi "Meta Description 1\|\"Meta Description 1\""; then
                HAS_META_THIS="true"
                HAS_META_COL="true"
            fi
            if echo "$HEADER" | grep -qi "H1-1\|\"H1-1\""; then
                HAS_H1_THIS="true"
                HAS_H1_COL="true"
            fi

            # Check domain
            if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                TARGET_DOMAIN_IN_CSV="true"
            fi

            # Categorize: comprehensive export (has all 3) or individual tabs
            if [ "$HAS_TITLE_THIS" = "true" ] && [ "$HAS_META_THIS" = "true" ] && [ "$HAS_H1_THIS" = "true" ]; then
                COMPREHENSIVE_CSV="$csv_file"
                COMPREHENSIVE_ROW_COUNT=$ROW_COUNT
                if [ "$ROW_COUNT" -gt "$MAX_ROW_COUNT" ]; then
                    MAX_ROW_COUNT=$ROW_COUNT
                fi
            elif [ "$HAS_TITLE_THIS" = "true" ]; then
                TITLES_CSV="$csv_file"
                TITLES_ROW_COUNT=$ROW_COUNT
                if [ "$ROW_COUNT" -gt "$MAX_ROW_COUNT" ]; then
                    MAX_ROW_COUNT=$ROW_COUNT
                fi
            elif [ "$HAS_META_THIS" = "true" ]; then
                META_CSV="$csv_file"
                META_ROW_COUNT=$ROW_COUNT
            elif [ "$HAS_H1_THIS" = "true" ]; then
                H1_CSV="$csv_file"
                H1_ROW_COUNT=$ROW_COUNT
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# Check report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")

    if grep -qE "[0-9]+" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_COUNTS="true"
    fi

    # Check for multiple issue category mentions
    CATEGORY_COUNT=0
    if grep -qiE "title|Title" "$REPORT_PATH" 2>/dev/null; then
        CATEGORY_COUNT=$((CATEGORY_COUNT + 1))
    fi
    if grep -qiE "meta description|Meta Description" "$REPORT_PATH" 2>/dev/null; then
        CATEGORY_COUNT=$((CATEGORY_COUNT + 1))
    fi
    if grep -qiE "\bH1\b|H1 tag|H1 tags" "$REPORT_PATH" 2>/dev/null; then
        CATEGORY_COUNT=$((CATEGORY_COUNT + 1))
    fi
    if [ "$CATEGORY_COUNT" -ge 2 ]; then
        REPORT_HAS_MULTIPLE_CATEGORIES="true"
    fi
fi

NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "new_csv_count": $NEW_CSV_COUNT,
    "titles_csv_found": len("$TITLES_CSV") > 0 or len("$COMPREHENSIVE_CSV") > 0,
    "meta_csv_found": len("$META_CSV") > 0 or len("$COMPREHENSIVE_CSV") > 0,
    "h1_csv_found": len("$H1_CSV") > 0 or len("$COMPREHENSIVE_CSV") > 0,
    "comprehensive_csv_found": len("$COMPREHENSIVE_CSV") > 0,
    "has_title_column": "$HAS_TITLE_COL" == "true",
    "has_meta_column": "$HAS_META_COL" == "true",
    "has_h1_column": "$HAS_H1_COL" == "true",
    "titles_row_count": $TITLES_ROW_COUNT,
    "meta_row_count": $META_ROW_COUNT,
    "h1_row_count": $H1_ROW_COUNT,
    "comprehensive_row_count": $COMPREHENSIVE_ROW_COUNT,
    "max_row_count": $MAX_ROW_COUNT,
    "target_domain_in_csv": "$TARGET_DOMAIN_IN_CSV" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_counts": "$REPORT_HAS_COUNTS" == "true",
    "report_has_multiple_categories": "$REPORT_HAS_MULTIPLE_CATEGORIES" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/on_page_seo_comprehensive_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/on_page_seo_comprehensive_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
