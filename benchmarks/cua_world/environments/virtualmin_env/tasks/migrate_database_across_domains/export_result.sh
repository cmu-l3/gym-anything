#!/bin/bash
echo "=== Exporting migrate_database_across_domains result ==="

source /workspace/scripts/task_utils.sh

if ! type virtualmin_db_query &>/dev/null; then
    virtualmin_db_query() { mysql -u root -pGymAnything123! -N -e "$1" 2>/dev/null || true; }
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TARGET_DOMAIN="brightstar.test"

# Check if catalog database exists (try both possible names)
CATALOG_DB_EXISTS="false"
CATALOG_DB_NAME=""

for dbname in brightstar_catalog brightstar_brightstar_catalog; do
    COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${dbname}';")
    if [ "${COUNT:-0}" -gt 0 ]; then
        CATALOG_DB_EXISTS="true"
        CATALOG_DB_NAME="$dbname"
        break
    fi
done

# Check if video_categories table exists
TABLE_EXISTS="false"
TABLE_COLUMNS=""
ROW_COUNT=0
CATEGORY_NAMES=""

if [ "$CATALOG_DB_EXISTS" = "true" ] && [ -n "$CATALOG_DB_NAME" ]; then
    TABLE_CHECK=$(virtualmin_db_query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${CATALOG_DB_NAME}' AND table_name='video_categories';")
    if [ "${TABLE_CHECK:-0}" -gt 0 ]; then
        TABLE_EXISTS="true"
        TABLE_COLUMNS=$(virtualmin_db_query "SELECT GROUP_CONCAT(column_name ORDER BY ordinal_position SEPARATOR ',') FROM information_schema.columns WHERE table_schema='${CATALOG_DB_NAME}' AND table_name='video_categories';")
        ROW_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM \`${CATALOG_DB_NAME}\`.video_categories;")
        CATEGORY_NAMES=$(virtualmin_db_query "SELECT GROUP_CONCAT(name SEPARATOR '|') FROM \`${CATALOG_DB_NAME}\`.video_categories;")
    fi
fi

# Check brightstar user grants to sakila (check all hosts)
SAKILA_GRANT="false"
for host in localhost 10.0.2.15 virtualmin.gym-anything.local '%'; do
    GRANTS=$(virtualmin_db_query "SHOW GRANTS FOR 'brightstar'@'${host}';" 2>/dev/null || echo "")
    if echo "$GRANTS" | grep -qi "sakila"; then
        SAKILA_GRANT="true"
        break
    fi
done

# Check required columns
HAS_ID="false"
HAS_NAME="false"
HAS_DESC="false"
HAS_CREATED_AT="false"
if [ -n "$TABLE_COLUMNS" ]; then
    echo "$TABLE_COLUMNS" | grep -qi "id" && HAS_ID="true"
    echo "$TABLE_COLUMNS" | grep -qi "name" && HAS_NAME="true"
    echo "$TABLE_COLUMNS" | grep -qi "description" && HAS_DESC="true"
    echo "$TABLE_COLUMNS" | grep -qi "created_at" && HAS_CREATED_AT="true"
fi

# Use Python for reliable JSON
python3 << PYEOF
import json

data = {
    "domain": "${TARGET_DOMAIN}",
    "catalog_db_exists": '${CATALOG_DB_EXISTS}' == 'true',
    "catalog_db_name": "${CATALOG_DB_NAME}",
    "table_exists": '${TABLE_EXISTS}' == 'true',
    "table_columns": "${TABLE_COLUMNS}",
    "has_id_column": '${HAS_ID}' == 'true',
    "has_name_column": '${HAS_NAME}' == 'true',
    "has_description_column": '${HAS_DESC}' == 'true',
    "has_created_at_column": '${HAS_CREATED_AT}' == 'true',
    "row_count": int('${ROW_COUNT}' or '0'),
    "category_names": "${CATEGORY_NAMES}",
    "sakila_grant": '${SAKILA_GRANT}' == 'true',
    "export_timestamp": "$(date -Iseconds)"
}

with open("/tmp/migrate_database_across_domains_result.json", "w") as f:
    json.dump(data, f, indent=2)

print(json.dumps(data, indent=2))
PYEOF

echo "=== Export Complete ==="
