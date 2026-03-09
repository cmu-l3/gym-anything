#!/bin/bash
set -e

# Ensure Vtiger directories are writable
chown -R www-data:www-data /var/www/html/vtigercrm
chmod -R 775 /var/www/html/vtigercrm

# Wait for MySQL to be ready
echo "Waiting for database..."
TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if php -r "new mysqli('${DB_HOST}', '${DB_USER}', '${DB_PASSWORD}', '${DB_NAME}', ${DB_PORT:-3306});" 2>/dev/null; then
        echo "Database is ready (${ELAPSED}s)"
        break
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
done

# Start Apache in foreground
exec apache2-foreground
