#!/bin/bash
# Note: no set -euo pipefail — commands need to be fault-tolerant

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
echo "PostgreSQL container: ${PG_CONTAINER:-NOT FOUND}"

date +%s > /tmp/task_start_time
rm -f /tmp/medical_pallet_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
else
    # Verify database is actually usable
    echo "Checking database usability..."
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')

    if [ "$DB_USABLE" != "1" ]; then
        echo "Database '${ODOO_DB}' not usable. Dropping and recreating..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2

        DB_CREATED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
        
        if [ "$DB_CREATED" = "1" ]; then
            echo "Initializing Odoo modules (this may take 3-5 minutes)..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
                -i base,stock,sale_management,purchase \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        fi

        # Restart Odoo web to pick up the new database
        echo "Restarting Odoo web server..."
        docker restart odoo-web 2>/dev/null || true

        echo "Waiting for Odoo web..."
        for _j in $(seq 1 90); do
            HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
            [ "$HTTP" = "200" ] && break
            sleep 5
        done

        # Wait for module registry to load
        echo "Waiting for module registry..."
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
    else
        echo "Database '${ODOO_DB}' is usable."

        # Check if modules are installed
        MODULES_INSTALLED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc \
            "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d ' \n')

        if [ "$MODULES_INSTALLED" != "1" ] && [ "$MODULES_INSTALLED" != "" ]; then
            echo "Modules not installed. Running module init..."
            docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
                -i base,stock,sale_management,purchase \
                --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -10 || true
            docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
                -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        fi

        echo "Restarting Odoo web to reload module registry..."
        docker restart odoo-web 2>/dev/null || true
        sleep 15
        
        for _j in $(seq 1 30); do
            HTTP=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8069/web/login" 2>/dev/null || echo "000")
            [ "$HTTP" = "200" ] && break
            sleep 2
        done
    fi

    # Populate Odoo database with specific data for this task
    echo "Configuring Odoo products and locations via XML-RPC..."
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
        print("Auth failed")
        sys.exit(1)
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)

    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    products_data = [
        'Med-Syringe 10ml',
        'Med-Saline 500ml',
        'Med-Bandage Roll',
        'Med-Gauze Pads 4x4',
        'Med-Surgical Gloves Size M',
        'Med-Surgical Gloves Size L'
    ]

    product_ids = {}
    for p_name in products_data:
        p_ids = execute('product.product', 'search', [[('name', '=', p_name)]])
        if not p_ids:
            p_id = execute('product.product', 'create', [{'name': p_name, 'type': 'product'}])
        else:
            p_id = p_ids[0]
        product_ids[p_name] = p_id

    wh = execute('stock.warehouse', 'search_read', [[]], {'fields': ['lot_stock_id'], 'limit': 1})
    if wh:
        stock_loc_id = wh[0]['lot_stock_id'][0]

        dep_loc_ids = execute('stock.location', 'search', [[('name', '=', 'Rapid Deployment'), ('location_id', '=', stock_loc_id)]])
        if not dep_loc_ids:
            dep_loc_id = execute('stock.location', 'create', [{
                'name': 'Rapid Deployment',
                'location_id': stock_loc_id,
                'usage': 'internal'
            }])
        else:
            dep_loc_id = dep_loc_ids[0]

        # Add bulk stock to WH/Stock
        for p_name, p_id in product_ids.items():
            quant_ids = execute('stock.quant', 'search', [[('product_id', '=', p_id), ('location_id', '=', stock_loc_id)]])
            if quant_ids:
                execute('stock.quant', 'write', [quant_ids, {'inventory_quantity': 5000}])
                for q in quant_ids:
                    execute('stock.quant', 'action_apply_inventory', [[q]])
            else:
                q_id = execute('stock.quant', 'create', [{
                    'product_id': p_id,
                    'location_id': stock_loc_id,
                    'inventory_quantity': 5000
                }])
                execute('stock.quant', 'action_apply_inventory', [[q_id]])

        # Clear any existing stock in Rapid Deployment
        dep_quants = execute('stock.quant', 'search', [[('location_id', '=', dep_loc_id)]])
        if dep_quants:
            execute('stock.quant', 'write', [dep_quants, {'inventory_quantity': 0}])
            for q in dep_quants:
                execute('stock.quant', 'action_apply_inventory', [[q]])

    # Disable Packages feature
    try:
        config_id = execute('res.config.settings', 'create', [{'group_stock_tracking_lot': False}])
        execute('res.config.settings', 'execute', [[config_id]])
    except Exception as e:
        print("Settings update warning (could be normal if already disabled):", e)

    print("Setup python script completed.")
except Exception as e:
    print(f"Error in setup python script: {e}")
PYEOF

fi

take_screenshot "/tmp/task_start.png" || true
echo "Setup complete."