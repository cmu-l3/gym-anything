#!/bin/bash
# Export script for Canonical Tag Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Canonical Tag Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/canonical_report.txt"

CANONICAL_CSV=""
CANONICAL_ROW_COUNT=0
HAS_CANONICAL_COL="false"
HAS_TYPE_COL="false"
HAS_SELF_REF_COL="false"
TARGET_DOMAIN_IN_CSV="false"
HAS_ACTUAL_CANONICAL_URLS="false"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_COUNTS="false"
REPORT_HAS_CANONICAL_TERMS="false"
SF_RUNNING="false"

if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            SAMPLE=$(head -15 "$csv_file" 2>/dev/null || echo "")

            # Identify canonical CSV
            # Must have "Canonical Link Element" or "Canonical" column
            IS_CANONICAL_CSV="false"
            if echo "$HEADER" | grep -qi "Canonical Link Element\|Canonical\|canonical"; then
                IS_CANONICAL_CSV="true"
            fi
            # Also match if content has canonical-related data patterns
            if echo "$SAMPLE" | grep -qi "canonical\|self.referencing\|Self Referencing"; then
                IS_CANONICAL_CSV="true"
            fi

            if [ "$IS_CANONICAL_CSV" = "true" ]; then
                CANONICAL_CSV="$csv_file"

                if echo "$HEADER" | grep -qi "Canonical Link Element\|Canonical"; then
                    HAS_CANONICAL_COL="true"
                fi
                if echo "$HEADER" | grep -qi "\bType\b"; then
                    HAS_TYPE_COL="true"
                fi
                if echo "$HEADER" | grep -qi "Self Referencing\|Self.Referencing"; then
                    HAS_SELF_REF_COL="true"
                fi

                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CANONICAL_ROW_COUNT=$((TOTAL_LINES - 1))

                if grep -qi "crawler-test.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_IN_CSV="true"
                fi

                # Check if canonical column contains actual URLs
                if grep -qiE "https?://" "$csv_file" 2>/dev/null; then
                    HAS_ACTUAL_CANONICAL_URLS="true"
                fi
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

    if grep -qiE "canonical|self.referencing|self referencing|missing|canonicalized|chain|duplicate" "$REPORT_PATH" 2>/dev/null; then
        REPORT_HAS_CANONICAL_TERMS="true"
    fi
fi

NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "new_csv_count": $NEW_CSV_COUNT,
    "canonical_csv_found": len("$CANONICAL_CSV") > 0,
    "canonical_csv_path": "$CANONICAL_CSV",
    "has_canonical_column": "$HAS_CANONICAL_COL" == "true",
    "has_type_column": "$HAS_TYPE_COL" == "true",
    "has_self_referencing_column": "$HAS_SELF_REF_COL" == "true",
    "canonical_row_count": $CANONICAL_ROW_COUNT,
    "target_domain_in_csv": "$TARGET_DOMAIN_IN_CSV" == "true",
    "has_actual_canonical_urls": "$HAS_ACTUAL_CANONICAL_URLS" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_counts": "$REPORT_HAS_COUNTS" == "true",
    "report_has_canonical_terms": "$REPORT_HAS_CANONICAL_TERMS" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/canonical_tag_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/canonical_tag_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
