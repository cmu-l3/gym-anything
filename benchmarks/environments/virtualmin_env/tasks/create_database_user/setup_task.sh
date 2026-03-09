#!/bin/bash
set -e
echo "=== Setting up create_database_user task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Verify acmecorp.test domain exists with MySQL
# ---------------------------------------------------------------
echo "--- Verifying acmecorp.test domain ---"
if ! virtualmin_domain_exists "acmecorp.test"; then
    echo "ERROR: acmecorp.test domain does not exist!"
    exit 1
fi

# Verify MySQL database exists
ACME_DB=$(virtualmin_db_query "SELECT SCHEMA_NAME FROM information_schema.schemata WHERE SCHEMA_NAME='acmecorp';" | tr -d '[:space:]')
if [ "$ACME_DB" != "acmecorp" ]; then
    echo "WARNING: acmecorp database not found, creating it..."
    virtualmin_db_query "CREATE DATABASE IF NOT EXISTS acmecorp;"
fi
echo "--- acmecorp database confirmed ---"

# Create a sample table with data so verification can test SELECT later
virtualmin_db_query "USE acmecorp; CREATE TABLE IF NOT EXISTS site_visitors (
    id INT AUTO_INCREMENT PRIMARY KEY,
    visitor_ip VARCHAR(45) NOT NULL,
    page_url VARCHAR(255) NOT NULL,
    visit_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    user_agent VARCHAR(512)
) ENGINE=InnoDB;"

virtualmin_db_query "USE acmecorp; INSERT IGNORE INTO site_visitors (id, visitor_ip, page_url, visit_time, user_agent) VALUES
    (1, '192.168.1.10', '/index.html', '2024-11-01 08:30:00', 'Mozilla/5.0'),
    (2, '10.0.0.55', '/about.html', '2024-11-01 09:15:00', 'Chrome/120.0'),
    (3, '172.16.0.100', '/products.html', '2024-11-01 10:00:00', 'Safari/17.0');"

echo "--- Sample table with data created in acmecorp database ---"

# ---------------------------------------------------------------
# 2. Record initial MySQL user count (for anti-gaming)
# ---------------------------------------------------------------
INITIAL_USER_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user;" | tr -d '[:space:]')
echo "$INITIAL_USER_COUNT" > /tmp/initial_mysql_user_count.txt
echo "--- Initial MySQL user count: $INITIAL_USER_COUNT ---"

# Ensure reports_reader does NOT already exist (clean state)
virtualmin_db_query "DROP USER IF EXISTS 'reports_reader'@'localhost';"
virtualmin_db_query "DROP USER IF EXISTS 'reports_reader'@'%';"
virtualmin_db_query "FLUSH PRIVILEGES;"
echo "--- Cleaned up any pre-existing reports_reader user ---"

# ---------------------------------------------------------------
# 3. Ensure Firefox is open and logged in to Virtualmin
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"
ensure_virtualmin_ready
sleep 3

# Navigate to acmecorp.test domain summary to save agent some clicks
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "${VIRTUALMIN_URL}/virtual-server/summary_domain.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
fi
sleep 5

# Focus and maximize Firefox
focus_firefox
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "--- Initial screenshot saved ---"

echo "=== Task setup complete ==="