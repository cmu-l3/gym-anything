#!/bin/bash
# Setup script for package_type_product_packaging task

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

# Detect actual PostgreSQL container name
PG_CONTAINER=""
for name in odoo-db odoo-postgres; do
    if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
        PG_CONTAINER="$name"
        break
    fi
done

if [ -z "$PG_CONTAINER" ]; then
    echo "ERROR: No PostgreSQL container found. Trying docker-compose..."
    cd /home/ga/odoo
    docker-compose up -d 2>/dev/null || true
    sleep 10
    for name in odoo-db odoo-postgres; do
        if docker exec "$name" pg_isready -U odoo 2>/dev/null; then
            PG_CONTAINER="$name"
            break
        fi
    done
fi

date +%s > /tmp/package_task_start_timestamp
rm -f /tmp/package_type_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Verify database is usable
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database not usable, creating basic structure..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" -i base,stock,sale_management,purchase --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        docker restart odoo-web 2>/dev/null || true
        sleep 15
    fi

    # Wait for module registry to load
    echo "Waiting for Odoo XML-RPC..."
    for _k in $(seq 1 30); do
        AUTH_OK=$(python3 -c "
import xmlrpc.client
try:
    c = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = c.authenticate('${ODOO_DB}', 'admin', 'admin', {})
    print('OK' if uid else 'FAIL')
except:
    print('FAIL')
" 2>/dev/null)
        [ "$AUTH_OK" = "OK" ] && break
        sleep 5
    done
    echo "Database ready. Auth: ${AUTH_OK}"

    # Setup the seed data via XML-RPC
    echo "Seeding task data..."
    python3 << PYEOF
import xmlrpc.client
import sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    if not uid:
        print("Auth failed.")
        sys.exit(1)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # 1. Clear existing packaging and package types to ensure clean slate
    try:
        packagings = execute('product.packaging', 'search', [[]])
        if packagings: execute('product.packaging', 'unlink', packagings)
        pkg_types = execute('stock.package.type', 'search', [[]])
        if pkg_types: execute('stock.package.type', 'unlink', pkg_types)
    except Exception as e:
        print("Warning cleaning packages:", e)

    # 2. Ensure Packages feature is disabled so the agent has to enable it
    try:
        settings_id = execute('res.config.settings', 'create', {'group_stock_tracking_lot': False})
        execute('res.config.settings', 'execute', [settings_id])
    except Exception as e:
        print("Warning disabling packages:", e)

    # 3. Create products
    products_to_create = [
        {'name': 'Makita XFD131 18V LXT Drill Kit', 'default_code': 'PKG-DRILL-001', 'detailed_type': 'product'},
        {'name': 'DeWalt DWE7491RS 10-Inch Table Saw', 'default_code': 'PKG-SAW-001', 'detailed_type': 'product'},
        {'name': 'Bosch GLL30 Self-Leveling Cross-Line Laser', 'default_code': 'PKG-LASER-001', 'detailed_type': 'product'},
        {'name': 'Irwin Marples M444 6-Piece Chisel Set', 'default_code': 'PKG-CHISEL-001', 'detailed_type': 'product'}
    ]
    
    for p in products_to_create:
        existing = execute('product.template', 'search', [[['default_code', '=', p['default_code']]]])
        if not existing:
            execute('product.template', 'create', p)

    print("Data seeded successfully.")
except Exception as e:
    print("Error during python setup:", e)
PYEOF

    echo "=== Setup Complete ==="
fi