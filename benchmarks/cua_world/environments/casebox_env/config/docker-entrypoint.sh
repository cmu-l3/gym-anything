#!/bin/bash
set -e

echo "=== Casebox entrypoint starting ==="

# Create supervisor log directory
mkdir -p /var/log/supervisor

# Wait for MySQL to be ready
echo "Waiting for MySQL..."
for i in $(seq 1 90); do
    if mysqladmin ping -h casebox-db -u root -pRootPass123 2>/dev/null; then
        echo "MySQL is ready after ${i}s"
        break
    fi
    if [ "$i" -eq 90 ]; then
        echo "ERROR: MySQL timeout"
        exit 1
    fi
    sleep 2
done

# Check if database has been initialized
TABLES=$(mysql -h casebox-db -u casebox -pCaseboxPass123 casebox -N -e "SHOW TABLES" 2>/dev/null | wc -l || echo "0")
echo "Found $TABLES tables in database"

if [ "$TABLES" -lt 5 ]; then
    echo "Importing default Casebox database schema..."
    mysql -h casebox-db -u casebox -pCaseboxPass123 casebox < /var/www/casebox/var/backup/cb_default.sql 2>&1 || {
        echo "WARNING: Default SQL import had issues, trying as root..."
        mysql -h casebox-db -u root -pRootPass123 casebox < /var/www/casebox/var/backup/cb_default.sql 2>&1 || true
    }

    # Verify import
    TABLES=$(mysql -h casebox-db -u casebox -pCaseboxPass123 casebox -N -e "SHOW TABLES" 2>/dev/null | wc -l || echo "0")
    echo "After import: $TABLES tables"

    # Import seed data if present
    if [ -f /seed/seed_cases.sql ]; then
        echo "Importing seed case data..."
        mysql -h casebox-db -u casebox -pCaseboxPass123 casebox < /seed/seed_cases.sql 2>&1 || \
            echo "WARNING: Seed data import had issues"
    fi

    # Update admin password to something known
    echo "Setting admin password..."
    ADMIN_HASH=$(php -r 'echo md5("Admin1234!");')
    mysql -h casebox-db -u casebox -pCaseboxPass123 casebox -e \
        "UPDATE users_groups SET password='${ADMIN_HASH}' WHERE name='root';" 2>/dev/null || true
fi

# Start Solr first (needed for index initialization)
echo "Starting Solr..."
/opt/solr/bin/solr start -force 2>/dev/null || true
sleep 5

# Initialize Solr indexes if not done
if [ ! -f /var/solr/data/casebox_initialized ]; then
    echo "Initializing Solr indexes..."
    cd /var/www/casebox
    php bin/console casebox:solr:create --env=default 2>/dev/null || true
    php bin/console casebox:solr:update --all=true --env=default 2>/dev/null || true
    php bin/console ca:cl --env=default 2>/dev/null || true
    touch /var/solr/data/casebox_initialized
    echo "Solr indexes initialized"
fi

# Stop Solr (supervisor will manage it)
/opt/solr/bin/solr stop -force 2>/dev/null || true
sleep 2

# Set final permissions
chmod -R 777 /var/www/casebox/var/cache /var/www/casebox/var/logs \
    /var/www/casebox/var/files /var/www/casebox/var/sessions 2>/dev/null || true

echo "=== Starting services via supervisord ==="
exec supervisord -n -c /etc/supervisor/conf.d/casebox.conf
