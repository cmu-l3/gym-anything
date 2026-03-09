#!/bin/bash
set -e
echo "=== Setting up import_database_dump task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
for svc in mariadb webmin apache2; do
    systemctl is-active --quiet "$svc" 2>/dev/null || systemctl start "$svc" 2>/dev/null || true
done
sleep 3

# Create the databases directory
mkdir -p /home/ga/databases

# Download Chinook MySQL dump from GitHub
echo "--- Downloading Chinook database dump ---"
CHINOOK_URL="https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_MySql_AutoIncrementPKs.sql"
CHINOOK_RAW="/tmp/chinook_raw.sql"

if ! curl -fsSL "$CHINOOK_URL" -o "$CHINOOK_RAW" 2>/dev/null; then
    echo "Primary URL failed, trying alternate..."
    CHINOOK_URL="https://github.com/lerocha/chinook-database/raw/master/ChinookDatabase/DataSources/Chinook_MySql_AutoIncrementPKs.sql"
    curl -fsSL -L "$CHINOOK_URL" -o "$CHINOOK_RAW"
fi

# Strip database-level statements to ensure clean import into specific target DB
# Remove DROP/CREATE DATABASE and USE statements
echo "--- Preparing SQL dump for import ---"
sed -e '/^DROP DATABASE/d' \
    -e '/^CREATE DATABASE/d' \
    -e '/^USE `/d' \
    -e 's/`Chinook`\.//g' \
    "$CHINOOK_RAW" > /home/ga/databases/chinook_backup.sql

# Fix line endings
sed -i 's/\r$//' /home/ga/databases/chinook_backup.sql

chown ga:ga /home/ga/databases
chown ga:ga /home/ga/databases/chinook_backup.sql
chmod 644 /home/ga/databases/chinook_backup.sql

echo "--- Prepared dump: $(wc -l < /home/ga/databases/chinook_backup.sql) lines ---"

# Ensure the database exists but is empty under acmecorp.test
echo "--- Creating empty acmecorp_chinook database ---"
# Drop if it somehow exists
mysql -u root -pGymAnything123! -e "DROP DATABASE IF EXISTS acmecorp_chinook;" 2>/dev/null || true

# Create via Virtualmin so it's associated with the domain
virtualmin create-database --domain acmecorp.test --name acmecorp_chinook --type mysql 2>/dev/null || {
    echo "Virtualmin create-database failed, creating manually..."
    mysql -u root -pGymAnything123! -e "CREATE DATABASE IF NOT EXISTS acmecorp_chinook;" 2>/dev/null
    # Grant permissions
    mysql -u root -pGymAnything123! -e "GRANT ALL ON acmecorp_chinook.* TO 'acmecorp'@'localhost';" 2>/dev/null || true
}

# Verify database is empty
TABLE_COUNT=$(mysql -u root -pGymAnything123! -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='acmecorp_chinook';" 2>/dev/null || echo "0")
echo "$TABLE_COUNT" > /tmp/initial_table_count.txt

# Ensure Firefox is open and logged into Virtualmin
ensure_virtualmin_ready

# Navigate to acmecorp.test domain database list
# Get domain ID for URL construction
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "https://localhost:10000/virtual-server/list_databases.cgi?dom=${DOMAIN_ID}"
else
    navigate_to "https://localhost:10000/virtual-server/index.cgi"
fi
sleep 5

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="