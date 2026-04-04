#!/bin/bash
# Export script for chinook_index_optimization task

echo "=== Exporting Chinook Index Optimization Result ==="

source /workspace/scripts/task_utils.sh

CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
REPORT_FILE="/home/ga/Documents/reports/index_report.txt"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

take_screenshot /tmp/chinook_index_task_end.png
sleep 1

# Check DBeaver 'Chinook' connection
CHINOOK_CONN_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    CHINOOK_CONN_FOUND=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    for k, v in config.get('connections', {}).items():
        name = v.get('name', '').lower()
        db_path = v.get('configuration', {}).get('database', '')
        if name == 'chinook' and 'chinook.db' in db_path:
            print('true')
            sys.exit(0)
    print('false')
except:
    print('false')
" 2>/dev/null || echo false)
fi

# Get current indexes in the database
CURRENT_INDEXES=$(sqlite3 "$CHINOOK_DB" \
    "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'" \
    2>/dev/null || echo "")

# Get baseline indexes
BASELINE_INDEXES=$(cat /tmp/baseline_chinook_indexes 2>/dev/null || echo "")

# Compute new indexes created by agent
NEW_INDEXES=$(python3 -c "
import sys
current = set()
baseline = set()

current_raw = '''$CURRENT_INDEXES'''
baseline_raw = '''$BASELINE_INDEXES'''

for line in current_raw.strip().split('\n'):
    if '|' in line:
        parts = line.split('|')
        current.add(parts[0].strip())
    elif line.strip():
        current.add(line.strip())

for line in baseline_raw.strip().split('\n'):
    if '|' in line:
        parts = line.split('|')
        baseline.add(parts[0].strip())
    elif line.strip():
        baseline.add(line.strip())

new = current - baseline
print('|'.join(new))
" 2>/dev/null || echo "")

NEW_INDEX_COUNT=$(echo "$NEW_INDEXES" | tr '|' '\n' | grep -c "." 2>/dev/null || echo 0)
echo "New indexes created: $NEW_INDEX_COUNT"
echo "New index names: $NEW_INDEXES"

# Check if indexes cover the right tables
HAS_TRACKS_INDEX="false"
HAS_INVOICES_INDEX="false"
HAS_MILLISECONDS_INDEX="false"
HAS_DATE_INDEX="false"
HAS_COMPOSER_INDEX="false"
DESCRIPTIVE_NAMES="false"

# Get full index details for new indexes
INDEX_DETAILS=$(sqlite3 "$CHINOOK_DB" \
    "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'IFK_%'" \
    2>/dev/null || echo "")

for idx_name in $(echo "$NEW_INDEXES" | tr '|' ' '); do
    if [ -z "$idx_name" ]; then continue; fi
    idx_lower=$(echo "$idx_name" | tr '[:upper:]' '[:lower:]')

    # Check table coverage
    IDX_TABLE=$(sqlite3 "$CHINOOK_DB" \
        "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='$idx_name'" \
        2>/dev/null || echo "")
    IDX_TABLE_LOWER=$(echo "$IDX_TABLE" | tr '[:upper:]' '[:lower:]')

    echo "$IDX_TABLE_LOWER" | grep -q "track" && HAS_TRACKS_INDEX="true"
    echo "$IDX_TABLE_LOWER" | grep -q "invoice" && HAS_INVOICES_INDEX="true"

    # Check column coverage by index name
    echo "$idx_lower" | grep -qE "milli|ms_|duration|ms$" && HAS_MILLISECONDS_INDEX="true"
    echo "$idx_lower" | grep -qE "date|invoicedate" && HAS_DATE_INDEX="true"
    echo "$idx_lower" | grep -qE "composer" && HAS_COMPOSER_INDEX="true"

    # Check if name is descriptive (not just idx_1, idx_2, etc.)
    if echo "$idx_lower" | grep -qE "idx_[a-z].*_[a-z]"; then
        DESCRIPTIVE_NAMES="true"
    fi
done

# If no clear naming but new indexes exist, check by looking at their SQL
if [ "$HAS_MILLISECONDS_INDEX" = "false" ] || [ "$HAS_DATE_INDEX" = "false" ]; then
    for idx_name in $(echo "$NEW_INDEXES" | tr '|' ' '); do
        if [ -z "$idx_name" ]; then continue; fi
        IDX_SQL=$(sqlite3 "$CHINOOK_DB" \
            "SELECT sql FROM sqlite_master WHERE type='index' AND name='$idx_name'" \
            2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
        echo "$IDX_SQL" | grep -qi "milliseconds" && HAS_MILLISECONDS_INDEX="true"
        echo "$IDX_SQL" | grep -qiE "invoicedate|invoice.*date" && HAS_DATE_INDEX="true"
        echo "$IDX_SQL" | grep -qi "composer" && HAS_COMPOSER_INDEX="true"
    done
fi

# Check report file
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_QUERY_A="false"
REPORT_HAS_QUERY_B="false"
REPORT_HAS_QUERY_C="false"
REPORT_HAS_INDEX_NAMES="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(get_file_size "$REPORT_FILE")
    REPORT_CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
    echo "$REPORT_CONTENT" | grep -qE "query.?a|milliseconds|duration|unitprice" && REPORT_HAS_QUERY_A="true"
    echo "$REPORT_CONTENT" | grep -qE "query.?b|invoicedate|invoice.*date|date.*range" && REPORT_HAS_QUERY_B="true"
    echo "$REPORT_CONTENT" | grep -qE "query.?c|composer|genre.*track|null.*composer" && REPORT_HAS_QUERY_C="true"
    echo "$REPORT_CONTENT" | grep -qE "create index|idx_|index name" && REPORT_HAS_INDEX_NAMES="true"
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
REPORT_CREATED_AFTER_START="false"
if [ -f "$REPORT_FILE" ]; then
    FILE_TIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || stat -f%m "$REPORT_FILE" 2>/dev/null || echo 0)
    [ "$FILE_TIME" -gt "$TASK_START" ] && REPORT_CREATED_AFTER_START="true"
fi

cat > /tmp/chinook_index_result.json << EOF
{
    "chinook_conn_found": $CHINOOK_CONN_FOUND,
    "new_index_count": $NEW_INDEX_COUNT,
    "new_indexes": "$NEW_INDEXES",
    "has_tracks_index": $HAS_TRACKS_INDEX,
    "has_invoices_index": $HAS_INVOICES_INDEX,
    "has_milliseconds_index": $HAS_MILLISECONDS_INDEX,
    "has_date_index": $HAS_DATE_INDEX,
    "has_composer_index": $HAS_COMPOSER_INDEX,
    "descriptive_names": $DESCRIPTIVE_NAMES,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_has_query_a": $REPORT_HAS_QUERY_A,
    "report_has_query_b": $REPORT_HAS_QUERY_B,
    "report_has_query_c": $REPORT_HAS_QUERY_C,
    "report_has_index_names": $REPORT_HAS_INDEX_NAMES,
    "report_created_after_start": $REPORT_CREATED_AFTER_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result:"
cat /tmp/chinook_index_result.json
echo ""
echo "=== Export Complete ==="
