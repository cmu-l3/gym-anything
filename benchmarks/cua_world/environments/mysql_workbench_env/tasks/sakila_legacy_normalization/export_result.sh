#!/bin/bash
# Export script for sakila_legacy_normalization task

echo "=== Exporting Legacy Normalization Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Database Credentials
DB_USER="root"
DB_PASS="GymAnything#2024"
TARGET_DB="rental_norm"

# Helper function to run SQL
run_sql() {
    mysql -u "$DB_USER" -p"$DB_PASS" -N -e "$1" 2>/dev/null
}

# 1. Check Database Existence
DB_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TARGET_DB';")
DB_EXISTS=${DB_EXISTS:-0}

# 2. Check Table Existence and Row Counts
check_table() {
    local table=$1
    local count=$(run_sql "SELECT COUNT(*) FROM $TARGET_DB.$table" 2>/dev/null)
    echo ${count:-0}
}

COUNT_CUSTOMERS=$(check_table "norm_customers")
COUNT_FILMS=$(check_table "norm_films")
COUNT_STORES=$(check_table "norm_stores")
COUNT_RENTALS=$(check_table "norm_rentals")

# 3. Check Constraints (PKs and FKs)
# Check PKs
count_pk() {
    local table=$1
    run_sql "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='$TARGET_DB' AND TABLE_NAME='$table' AND CONSTRAINT_TYPE='PRIMARY KEY';"
}

PK_CUSTOMERS=$(count_pk "norm_customers")
PK_FILMS=$(count_pk "norm_films")
PK_STORES=$(count_pk "norm_stores")
PK_RENTALS=$(count_pk "norm_rentals")

# Check FKs on norm_rentals
FK_COUNT=$(run_sql "SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA='$TARGET_DB' AND TABLE_NAME='norm_rentals' AND REFERENCED_TABLE_NAME IS NOT NULL;")
FK_COUNT=${FK_COUNT:-0}

# Check Unique Constraint on Customer Email
UNIQUE_EMAIL=$(run_sql "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='$TARGET_DB' AND TABLE_NAME='norm_customers' AND COLUMN_NAME='email' AND NON_UNIQUE=0;")
UNIQUE_EMAIL=${UNIQUE_EMAIL:-0}

# 4. Check View Existence
VIEW_EXISTS=$(run_sql "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA='$TARGET_DB' AND TABLE_NAME='v_rental_denormalized';")
VIEW_EXISTS=${VIEW_EXISTS:-0}

# 5. Check View Functionality (Does it return rows?)
VIEW_ROWS=0
if [ "$VIEW_EXISTS" -eq 1 ]; then
    VIEW_ROWS=$(run_sql "SELECT COUNT(*) FROM $TARGET_DB.v_rental_denormalized" 2>/dev/null)
    VIEW_ROWS=${VIEW_ROWS:-0}
fi

# 6. Check CSV Export
CSV_FILE="/home/ga/Documents/exports/normalized_customers.csv"
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$CSV_FILE" 2>/dev/null || echo "0")
    # Subtract 1 for header
    TOTAL_LINES=$(wc -l < "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# 7. Check if MySQL Workbench was used (process check)
WORKBENCH_RUNNING=$(pgrep -f "mysql-workbench" > /dev/null && echo "true" || echo "false")

# Create JSON Result
cat > /tmp/normalization_result.json << EOF
{
    "db_exists": $DB_EXISTS,
    "count_customers": $COUNT_CUSTOMERS,
    "count_films": $COUNT_FILMS,
    "count_stores": $COUNT_STORES,
    "count_rentals": $COUNT_RENTALS,
    "pk_customers": $PK_CUSTOMERS,
    "pk_films": $PK_FILMS,
    "pk_stores": $PK_STORES,
    "pk_rentals": $PK_RENTALS,
    "fk_count_rentals": $FK_COUNT,
    "unique_email": $UNIQUE_EMAIL,
    "view_exists": $VIEW_EXISTS,
    "view_rows": $VIEW_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "workbench_running": $WORKBENCH_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Export complete. JSON saved to /tmp/normalization_result.json"
cat /tmp/normalization_result.json