#!/bin/bash
echo "=== Setting up create_mysql_database task ==="

source /workspace/scripts/task_utils.sh

# Remove any existing 'shop' database for brightstar.test from a previous run
for db in brightstar_shop brightstar_brightstar_shop; do
    if mysql_database_exists "$db"; then
        echo "WARNING: Database $db already exists, removing it..."
        virtualmin_db_query "DROP DATABASE IF EXISTS \`${db}\`;"
        sleep 1
    fi
done

# Ensure Virtualmin is accessible in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to the MySQL Databases page for brightstar.test
# list_databases.cgi is the correct Virtualmin 8.x name; uses numeric domain ID
BRIGHTSTAR_ID=$(get_domain_id "brightstar.test")
navigate_to "https://localhost:10000/virtual-server/list_databases.cgi?dom=${BRIGHTSTAR_ID}"
sleep 5

take_screenshot /tmp/create_mysql_database_start.png
echo "=== create_mysql_database task setup complete ==="
echo "Agent should see the MySQL Databases page for brightstar.test in Firefox."
