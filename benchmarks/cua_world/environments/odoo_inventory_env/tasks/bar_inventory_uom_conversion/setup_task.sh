#!/bin/bash
# Setup script for bar_inventory_uom_conversion task

source /workspace/scripts/task_utils.sh

ODOO_URL="http://localhost:8069"
ODOO_DB="odoo_inventory"
ODOO_USER="admin"
ODOO_PASS="admin"

# Locate PostgreSQL container
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

date +%s > /tmp/task_start_time.txt
rm -f /tmp/uom_conversion_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
    exit 1
fi

echo "Checking database usability..."
DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')

if [ "$DB_USABLE" != "1" ]; then
    echo "Database '${ODOO_DB}' not usable. Dropping and recreating..."
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
    sleep 2
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
    sleep 2

    echo "Initializing Odoo modules (this may take 3-5 minutes)..."
    docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
        -i base,stock,sale_management,purchase \
        --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

    docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
        -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true

    echo "Restarting Odoo web server..."
    docker restart odoo-web 2>/dev/null || true

    echo "Waiting for Odoo web..."
    for _j in $(seq 1 90); do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
        [ "$HTTP" = "200" ] && break
        sleep 5
    done
else
    echo "Database is usable."
    MODULES_INSTALLED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc \
        "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d ' \n')
    
    if [ "$MODULES_INSTALLED" != "1" ] && [ "$MODULES_INSTALLED" != "" ]; then
        echo "Modules not installed. Running module init..."
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
            -i base,stock,sale_management,purchase \
            --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -10 || true
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
            -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        docker restart odoo-web 2>/dev/null || true
    fi
fi

# Wait for XMLRPC registry to be fully available
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

echo "Setting up task specific records via Python script..."

cat << 'PYEOF' > /tmp/setup_bar.py
import xmlrpc.client

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
uid = common.authenticate(db, 'admin', password, {})
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

def execute(model, method, args=None, **kwargs):
    return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

# 1. Disable UoM feature by removing group from admin user
try:
    uom_group = execute('ir.model.data', 'search_read', [[('module', '=', 'uom'), ('name', '=', 'group_uom')]], ['res_id'])
    if uom_group:
        execute('res.users', 'write', [2], {'groups_id': [(3, uom_group[0]['res_id'])]})
except Exception as e:
    print("Failed to remove UoM group:", e)

# 2. Get the 'Units' UoM id
uom_unit = execute('uom.uom', 'search_read', [[('name', 'ilike', 'Unit')]], ['id'], limit=1)
uom_id = uom_unit[0]['id'] if uom_unit else 1

# 3. Create Vendor
vendor_id = execute('res.partner', 'create', [{
    'name': "Southern Glazer's Wine & Spirits",
    'supplier_rank': 1
}])

# 4. Create Products
prod1_id = execute('product.product', 'create', [{
    'name': "Hendrick's Gin 750ml",
    'type': 'product',
    'default_code': 'BAR-GIN-001',
    'uom_id': uom_id,
    'uom_po_id': uom_id
}])

prod2_id = execute('product.product', 'create', [{
    'name': "Woodford Reserve Bourbon 750ml",
    'type': 'product',
    'default_code': 'BAR-BBN-001',
    'uom_id': uom_id,
    'uom_po_id': uom_id
}])

# 5. Create Draft PO
po_id = execute('purchase.order', 'create', [{
    'partner_id': vendor_id,
    'order_line': [
        (0, 0, {
            'product_id': prod1_id,
            'product_qty': 3.0,
            'product_uom': uom_id,
            'price_unit': 35.0,
        }),
        (0, 0, {
            'product_id': prod2_id,
            'product_qty': 5.0,
            'product_uom': uom_id,
            'price_unit': 42.0,
        })
    ]
}])

print("Python setup completed successfully.")
PYEOF

python3 /tmp/setup_bar.py

take_screenshot /tmp/task_initial_state.png ga || true

echo "=== Task Setup Complete ==="