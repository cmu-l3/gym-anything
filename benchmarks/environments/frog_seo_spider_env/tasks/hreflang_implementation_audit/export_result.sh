#!/bin/bash
# Export script for Hreflang Implementation Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Hreflang Implementation Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/hreflang_report.txt"

HREFLANG_CSV=""
HREFLANG_ROW_COUNT=0
HAS_LANGUAGE_COLUMN="false"
HAS_LANGUAGE_CODES="false"
UNIQUE_LANGUAGES=""
TARGET_DOMAIN_IN_CSV="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_LANGUAGE_CODES="false"
REPORT_HAS_ERROR_TYPES="false"
SF_RUNNING="false"

if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Find hreflang CSV in exports directory
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            SAMPLE=$(head -20 "$csv_file" 2>/dev/null || echo "")

            # Identify a hreflang CSV
            # Hreflang exports have columns: "Language", "Self Referencing", "Missing Return Link", etc.
            IS_HREFLANG_CSV="false"
            if echo "$HEADER" | grep -qi "Language\|hreflang\|Self Referencing\|Missing Return"; then
                IS_HREFLANG_CSV="true"
            fi
            # Also check if the file contains language codes like "en", "de", "fr", "x-default"
            if echo "$SAMPLE" | grep -qiE ",en,|,de,|,fr,|,x-default,|en-|de-|fr-"; then
                IS_HREFLANG_CSV="true"
            fi

            if [ "$IS_HREFLANG_CSV" = "true" ]; then
                HREFLANG_CSV="$csv_file"

                if echo "$HEADER" | grep -qi "Language\|hreflang"; then
                    HAS_LANGUAGE_COLUMN="true"
                fi

                # Check for language codes
                if grep -qiE "^https?://|,en,|,de,|,fr,|,es,|,x-default,|,en-|,de-|,fr-" "$csv_file" 2>/dev/null; then
                    HAS_LANGUAGE_CODES="true"
                fi

                # Count data rows
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                HREFLANG_ROW_COUNT=$((TOTAL_LINES - 1))

                # Check target domain
                if grep -qi "crawler-test.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_IN_CSV="true"
                fi

                # Get unique language codes (2-char codes common in hreflang)
                UNIQUE_LANGUAGES=$(grep -oiE ",en,|,de,|,fr,|,es,|,ja,|,zh,|,pt,|,it,|x-default" "$csv_file" 2>/dev/null | sort -u | tr -d ',' | tr '\n' ' ' | xargs || echo "")
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# Check text report
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")

    # Check for language code mentions
    if grep -qiE "\ben\b|\bde\b|\bfr\b|\bes\b|x-default|language code" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_LANGUAGE_CODES="true"
    fi

    # Check for error type mentions
    if grep -qiE "missing return|return link|invalid|error|non.canonical|orphan|inconsistent" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_ERROR_TYPES="true"
    fi
fi

NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "new_csv_count": $NEW_CSV_COUNT,
    "hreflang_csv_found": len("$HREFLANG_CSV") > 0,
    "hreflang_csv_path": "$HREFLANG_CSV",
    "has_language_column": "$HAS_LANGUAGE_COLUMN" == "true",
    "has_language_codes": "$HAS_LANGUAGE_CODES" == "true",
    "hreflang_row_count": $HREFLANG_ROW_COUNT,
    "unique_languages_found": "$UNIQUE_LANGUAGES".strip(),
    "target_domain_in_csv": "$TARGET_DOMAIN_IN_CSV" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_language_codes": "$REPORT_HAS_LANGUAGE_CODES" == "true",
    "report_has_error_types": "$REPORT_HAS_ERROR_TYPES" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/hreflang_implementation_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/hreflang_implementation_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
