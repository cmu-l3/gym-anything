#!/bin/bash
# Setup script for sakila_audit_system task

echo "=== Setting up Sakila Audit System Task ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_mysql_running &>/dev/null; then
    is_mysql_running() { mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

date +%s > /tmp/task_start_timestamp

if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL..."
    systemctl start mysql
    sleep 5
fi

# Clean up any artifacts from previous runs
echo "Cleaning previous state..."
mysql -u root -p'GymAnything#2024' sakila -e "
    DROP TRIGGER IF EXISTS tr_customer_audit;
    DROP PROCEDURE IF EXISTS sp_calculate_loyalty_tiers;
    DROP TABLE IF EXISTS customer_audit_log;
    DROP TABLE IF EXISTS customer_loyalty;
" 2>/dev/null || true

# Create the supporting tables that the agent will use
echo "Creating supporting tables..."

mysql -u root -p'GymAnything#2024' sakila -e "
CREATE TABLE customer_audit_log (
    log_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    customer_id SMALLINT UNSIGNED NOT NULL,
    old_email  VARCHAR(50),
    new_email  VARCHAR(50),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
" 2>/dev/null

mysql -u root -p'GymAnything#2024' sakila -e "
CREATE TABLE customer_loyalty (
    customer_id  SMALLINT UNSIGNED PRIMARY KEY,
    first_name   VARCHAR(45) NOT NULL,
    last_name    VARCHAR(45) NOT NULL,
    rental_count INT NOT NULL DEFAULT 0,
    tier         VARCHAR(20) NOT NULL,
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
" 2>/dev/null

# Grant privileges to ga user on new tables
mysql -u root -p'GymAnything#2024' -e "
    GRANT ALL PRIVILEGES ON sakila.customer_audit_log TO 'ga'@'localhost';
    GRANT ALL PRIVILEGES ON sakila.customer_loyalty TO 'ga'@'localhost';
    FLUSH PRIVILEGES;
" 2>/dev/null || true

# Verify tables created
TABLE_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM TABLES
    WHERE TABLE_SCHEMA='sakila'
    AND TABLE_NAME IN ('customer_audit_log', 'customer_loyalty')
" 2>/dev/null)
echo "Supporting tables created: ${TABLE_COUNT:-0}/2"

# Record initial baseline (trigger and procedure should NOT exist yet)
TRIGGER_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM TRIGGERS
    WHERE TRIGGER_SCHEMA='sakila' AND TRIGGER_NAME='tr_customer_audit'
" 2>/dev/null)
PROC_COUNT=$(mysql -u root -p'GymAnything#2024' information_schema -N -e "
    SELECT COUNT(*) FROM ROUTINES
    WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_NAME='sp_calculate_loyalty_tiers'
    AND ROUTINE_TYPE='PROCEDURE'
" 2>/dev/null)
AUDIT_LOG_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM customer_audit_log;
" 2>/dev/null)
LOYALTY_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
    SELECT COUNT(*) FROM customer_loyalty;
" 2>/dev/null)

echo "${TRIGGER_COUNT:-0}" > /tmp/initial_trigger_count
echo "${PROC_COUNT:-0}" > /tmp/initial_proc_count
echo "${AUDIT_LOG_COUNT:-0}" > /tmp/initial_audit_log_count
echo "${LOYALTY_COUNT:-0}" > /tmp/initial_loyalty_count

echo "Baseline: trigger=${TRIGGER_COUNT:-0} proc=${PROC_COUNT:-0} audit_log=${AUDIT_LOG_COUNT:-0} loyalty=${LOYALTY_COUNT:-0}"

# Verify Sakila customer data
CUSTOMER_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer;" 2>/dev/null)
echo "Sakila customers available: ${CUSTOMER_COUNT:-0}"

# Clean previous export
rm -f /home/ga/Documents/exports/customer_loyalty.csv 2>/dev/null || true

if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 10
fi
focus_workbench

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="
echo "Tables customer_audit_log and customer_loyalty created in sakila. Agent must create trigger, procedure, test, and export."
