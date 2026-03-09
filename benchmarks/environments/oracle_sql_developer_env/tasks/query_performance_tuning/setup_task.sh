#!/bin/bash
# Setup script for Query Performance Tuning task
echo "=== Setting up Query Performance Tuning task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle container
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# --- Clean up previous run artifacts ---
echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.performance_orders PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE hr.tuning_queries PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "hr" 2>/dev/null || true

# --- Create PERFORMANCE_ORDERS table (11,449 rows from real HR employee cross-product) ---
# Data is derived from real HR employees: each row has real employee_id values as customer/salesperson,
# real salary-derived order_amounts, and real hire_date-derived order_dates.
echo "Creating HR.PERFORMANCE_ORDERS table (11,449 rows from employee cross-product)..."

oracle_query "CREATE TABLE hr.performance_orders AS
SELECT
    (e1.employee_id - 99) * 200 + (e2.employee_id - 99) AS order_id,
    e1.employee_id                                         AS customer_id,
    e2.employee_id                                         AS salesperson_id,
    ROUND(e1.salary * (MOD(e2.employee_id - 99, 10) + 1) * 0.12, 2) AS order_amount,
    ADD_MONTHS(DATE '2020-01-01', MOD(e1.employee_id + e2.employee_id, 36))
        + MOD(e2.department_id, 28)                       AS order_date,
    e1.department_id                                       AS customer_dept_id,
    e2.department_id                                       AS salesperson_dept_id
FROM hr.employees e1
CROSS JOIN hr.employees e2;
EXIT;" "hr"

PERF_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM hr.performance_orders;" "hr" | tr -d '[:space:]')
echo "PERFORMANCE_ORDERS created with $PERF_COUNT rows"

# --- Create TUNING_QUERIES table with 5 problematic queries ---
echo "Creating HR.TUNING_QUERIES table..."
oracle_query "CREATE TABLE hr.tuning_queries (
    query_id          NUMBER PRIMARY KEY,
    description       VARCHAR2(200),
    sql_text          VARCHAR2(4000),
    performance_issue VARCHAR2(500)
);
EXIT;" "hr"

oracle_query "INSERT INTO hr.tuning_queries VALUES (
    1,
    'High-value order filter',
    'SELECT order_id, customer_id, order_amount, order_date FROM hr.performance_orders WHERE order_amount > 9000 ORDER BY order_amount DESC',
    'No index on ORDER_AMOUNT causes full table scan (TABLE ACCESS FULL)'
);
INSERT INTO hr.tuning_queries VALUES (
    2,
    'Date range order search',
    'SELECT order_id, customer_id, order_date FROM hr.performance_orders WHERE order_date >= DATE ''2021-06-01'' AND order_date < DATE ''2022-01-01''',
    'No index on ORDER_DATE causes full table scan (TABLE ACCESS FULL)'
);
INSERT INTO hr.tuning_queries VALUES (
    3,
    'Department-level aggregation',
    'SELECT customer_dept_id, COUNT(*) AS order_count, AVG(order_amount) AS avg_amt, SUM(order_amount) AS total_amt FROM hr.performance_orders GROUP BY customer_dept_id ORDER BY total_amt DESC',
    'No index on CUSTOMER_DEPT_ID; full scan required for GROUP BY aggregation'
);
INSERT INTO hr.tuning_queries VALUES (
    4,
    'Salesperson order lookup with employee join',
    'SELECT po.order_id, po.customer_id, po.order_amount, e.first_name, e.last_name FROM hr.performance_orders po JOIN hr.employees e ON po.salesperson_id = e.employee_id WHERE po.customer_id BETWEEN 100 AND 120',
    'No index on CUSTOMER_ID; nested loop join requires full scan of performance_orders'
);
INSERT INTO hr.tuning_queries VALUES (
    5,
    'Sub-query based customer segmentation',
    'SELECT * FROM hr.performance_orders WHERE customer_id IN (SELECT employee_id FROM hr.employees WHERE department_id IN (10, 20, 30, 40, 50)) ORDER BY order_date',
    'Full scan on PERFORMANCE_ORDERS and no ORDER_DATE index for sort; sub-query drives full scan'
);
COMMIT;
EXIT;" "hr"

echo "5 tuning queries inserted"

# Record initial index count on performance_orders (should be 0 - CTAS creates no indexes)
INITIAL_INDEX_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM all_indexes WHERE owner = 'HR' AND table_name = 'PERFORMANCE_ORDERS';" "system" | tr -d '[:space:]')
INITIAL_INDEX_COUNT=${INITIAL_INDEX_COUNT:-0}
printf '%s' "$INITIAL_INDEX_COUNT" > /tmp/initial_perf_order_index_count
echo "Initial index count on PERFORMANCE_ORDERS: $INITIAL_INDEX_COUNT"

# Ensure export directory exists
sudo -u ga mkdir -p /home/ga/Documents/exports 2>/dev/null || mkdir -p /home/ga/Documents/exports 2>/dev/null || true

# Pre-configure HR connection
ensure_hr_connection "HR Database" "hr" "$HR_PWD"
sleep 2

if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
    open_hr_connection_in_sqldeveloper
fi

echo "=== Query Performance Tuning setup complete ==="
echo "PERFORMANCE_ORDERS: $PERF_COUNT rows, 0 indexes (agent must analyze and create indexes)"
echo "TUNING_QUERIES: 5 problematic queries documented"
