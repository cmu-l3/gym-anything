#!/bin/bash
# Setup script for sakila_performance_optimization task

echo "=== Setting up Sakila Performance Optimization Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Ensure MySQL is running
if ! mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Drop any pre-existing view/procedure from previous runs
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP VIEW IF EXISTS v_monthly_revenue;
    DROP PROCEDURE IF EXISTS sp_monthly_revenue;
" 2>/dev/null || true

# Clean previous export
rm -f /home/ga/Documents/exports/monthly_revenue_2005.csv 2>/dev/null || true

echo "Dropping three performance-critical indexes from Sakila to simulate degradation..."

# For each FK-backed index, we must: (1) drop FK constraint, then (2) drop the index.
# MySQL refuses to DROP INDEX on an index that backs a FOREIGN KEY constraint.
# We look up FK names dynamically to handle any MySQL version differences.

drop_fk_and_index() {
    local table=$1
    local column=$2
    echo "  -- Dropping FK+index on ${table}.${column} --"

    # Find the FK constraint name for this column
    local fk_name
    fk_name=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT CONSTRAINT_NAME FROM KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='${table}'
          AND COLUMN_NAME='${column}' AND REFERENCED_TABLE_NAME IS NOT NULL
        LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    if [ -n "$fk_name" ]; then
        mysql -u root -p'GymAnything#2024' sakila -e "
            ALTER TABLE ${table} DROP FOREIGN KEY \`${fk_name}\`;
        " 2>/dev/null \
            && echo "    Dropped FK: ${fk_name}" \
            || echo "    FK ${fk_name} could not be dropped (may not exist)"
    else
        echo "    No FK found for ${table}.${column}"
    fi

    # Find a standalone single-column index on this column (not PRIMARY, not composite)
    local idx_name
    idx_name=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
        SELECT s1.INDEX_NAME
        FROM STATISTICS s1
        WHERE s1.TABLE_SCHEMA='sakila' AND s1.TABLE_NAME='${table}'
          AND s1.COLUMN_NAME='${column}' AND s1.SEQ_IN_INDEX=1
          AND s1.INDEX_NAME != 'PRIMARY'
          AND (
            SELECT COUNT(*) FROM STATISTICS s2
            WHERE s2.TABLE_SCHEMA='sakila' AND s2.TABLE_NAME='${table}'
              AND s2.INDEX_NAME = s1.INDEX_NAME
          ) = 1
        LIMIT 1
    " 2>/dev/null | tr -d '[:space:]')

    if [ -n "$idx_name" ]; then
        mysql -u root -p'GymAnything#2024' sakila -e "
            DROP INDEX \`${idx_name}\` ON ${table};
        " 2>/dev/null \
            && echo "    Dropped index: ${idx_name} on ${table}" \
            || echo "    Index ${idx_name} could not be dropped"
    else
        echo "    No standalone index found on ${table}.${column} to drop"
    fi
}

drop_fk_and_index rental customer_id
drop_fk_and_index payment rental_id
drop_fk_and_index inventory film_id

# Verify indexes were dropped (count standalone single-column indexes for the 3 columns)
REMAINING=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT SUM(cnt) FROM (
        SELECT COUNT(DISTINCT s1.INDEX_NAME) AS cnt
        FROM STATISTICS s1
        WHERE s1.TABLE_SCHEMA='sakila' AND s1.TABLE_NAME='rental'
          AND s1.COLUMN_NAME='customer_id' AND s1.SEQ_IN_INDEX=1
          AND s1.INDEX_NAME != 'PRIMARY'
          AND (SELECT COUNT(*) FROM STATISTICS s2
               WHERE s2.TABLE_SCHEMA='sakila' AND s2.TABLE_NAME='rental'
                 AND s2.INDEX_NAME=s1.INDEX_NAME) = 1
        UNION ALL
        SELECT COUNT(DISTINCT s1.INDEX_NAME) AS cnt
        FROM STATISTICS s1
        WHERE s1.TABLE_SCHEMA='sakila' AND s1.TABLE_NAME='payment'
          AND s1.COLUMN_NAME='rental_id' AND s1.SEQ_IN_INDEX=1
          AND s1.INDEX_NAME != 'PRIMARY'
          AND (SELECT COUNT(*) FROM STATISTICS s2
               WHERE s2.TABLE_SCHEMA='sakila' AND s2.TABLE_NAME='payment'
                 AND s2.INDEX_NAME=s1.INDEX_NAME) = 1
        UNION ALL
        SELECT COUNT(DISTINCT s1.INDEX_NAME) AS cnt
        FROM STATISTICS s1
        WHERE s1.TABLE_SCHEMA='sakila' AND s1.TABLE_NAME='inventory'
          AND s1.COLUMN_NAME='film_id' AND s1.SEQ_IN_INDEX=1
          AND s1.INDEX_NAME != 'PRIMARY'
          AND (SELECT COUNT(*) FROM STATISTICS s2
               WHERE s2.TABLE_SCHEMA='sakila' AND s2.TABLE_NAME='inventory'
                 AND s2.INDEX_NAME=s1.INDEX_NAME) = 1
    ) totals
" 2>/dev/null)
REMAINING=${REMAINING:-99}
echo "${REMAINING}" > /tmp/initial_missing_indexes
echo "Remaining standalone performance indexes: ${REMAINING} (should be 0 after drops)"

# Record initial baseline counts (should be 0)
VIEW_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM VIEWS
    WHERE TABLE_SCHEMA='sakila' AND TABLE_NAME='v_monthly_revenue'
" 2>/dev/null)
PROC_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES
    WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_monthly_revenue' AND ROUTINE_TYPE='PROCEDURE'
" 2>/dev/null)
echo "${VIEW_COUNT:-0}" > /tmp/initial_view_count
echo "${PROC_COUNT:-0}" > /tmp/initial_proc_count

# Ensure Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi
focus_workbench

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="
echo "Three indexes dropped from sakila. Agent must diagnose with EXPLAIN and restore them."
