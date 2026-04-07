#!/bin/bash

source /workspace/scripts/task_utils.sh

# Start timestamps
date +%s > /tmp/bulk_import_task_start_timestamp
rm -f /tmp/bulk_import_result.json

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

if [ -n "$PG_CONTAINER" ]; then
    echo "Database '${ODOO_DB}' usability check..."
    DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')
    
    if [ "$DB_USABLE" != "1" ]; then
        echo "Database not usable. Setting up..."
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
        sleep 2
        docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
        sleep 2
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
            -i base,stock,sale_management,purchase \
            --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" \
            -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        docker restart odoo-web 2>/dev/null || true
        sleep 10
    fi
    
    # Wait for module registry to load
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
fi

echo "Setting up environment for bulk import task..."

# 1. Create the CSV file on the desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/product_catalog.csv << 'EOF'
Product Name,SKU,Category,Unit Cost,Retail Price,Type,Weight (kg)
Anker PowerCore 10000mAh Portable Charger,ELEC-001,All / Electronics,18.50,29.99,Storable Product,0.18
Logitech M720 Triathlon Multi-Device Mouse,ELEC-002,All / Electronics,32.00,49.99,Storable Product,0.14
SanDisk Ultra 128GB microSDXC UHS-I Card,ELEC-003,All / Electronics,9.80,18.99,Storable Product,0.01
JBL Tune 510BT Wireless On-Ear Headphones,ELEC-004,All / Electronics,22.00,39.99,Storable Product,0.16
Samsung T7 Portable SSD 500GB,ELEC-005,All / Electronics,42.00,69.99,Storable Product,0.06
TP-Link Archer T3U AC1300 USB WiFi Adapter,ELEC-006,All / Electronics,11.50,19.99,Storable Product,0.05
Corsair K55 RGB Pro Gaming Keyboard,ELEC-007,All / Electronics,28.00,49.99,Storable Product,0.86
Logitech C920 HD Pro Webcam 1080p,ELEC-008,All / Electronics,38.00,64.99,Storable Product,0.16
WD Elements 2TB Portable External HDD,ELEC-009,All / Electronics,45.00,74.99,Storable Product,0.13
Anker 735 Charger GaNPrime 65W,ELEC-010,All / Electronics,26.00,44.99,Storable Product,0.11
HyperX Cloud Stinger 2 Gaming Headset,ELEC-011,All / Electronics,20.00,34.99,Storable Product,0.28
Razer DeathAdder Essential Gaming Mouse,ELEC-012,All / Electronics,14.00,24.99,Storable Product,0.10
EOF
chown ga:ga /home/ga/Desktop/product_catalog.csv
chmod 644 /home/ga/Desktop/product_catalog.csv

# 2. Use XML-RPC to prepare Odoo: Ensure Category exists, delete existing ELEC-* products
python3 << PYEOF
import xmlrpc.client, json, sys

url = 'http://localhost:8069'
db = 'odoo_inventory'
password = 'admin'

try:
    common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common', allow_none=True)
    uid = common.authenticate(db, 'admin', password, {})
    if not uid:
        print("Failed to authenticate.")
        sys.exit(0)
        
    models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object', allow_none=True)
    def execute(model, method, args=None, **kwargs):
        return models.execute_kw(db, uid, password, model, method, args or [], kwargs)

    # Clean existing ELEC-001 through ELEC-012 products
    elec_skus = [f"ELEC-{i:03d}" for i in range(1, 13)]
    existing = execute('product.template', 'search', [[['default_code', 'in', elec_skus]]])
    if existing:
        execute('product.template', 'unlink', [existing])
        print(f"Removed {len(existing)} existing ELEC- products.")

    # Find or create 'All / Electronics' category
    cat_id = None
    all_cat = execute('product.category', 'search_read', [[['name', '=', 'All']]], fields=['id'], limit=1)
    if all_cat:
        parent_id = all_cat[0]['id']
        elec_cat = execute('product.category', 'search', [[['name', '=', 'Electronics'], ['parent_id', '=', parent_id]]])
        if elec_cat:
            cat_id = elec_cat[0]
        else:
            cat_id = execute('product.category', 'create', [{'name': 'Electronics', 'parent_id': parent_id}])
    
    # Store initial state
    total_products = execute('product.template', 'search_count', [[]])
    initial_state = {
        'total_products': total_products,
        'category_id': cat_id
    }
    with open('/tmp/bulk_import_initial_state.json', 'w') as f:
        json.dump(initial_state, f)
        
    print(f"Setup complete. Initial product count: {total_products}")

except Exception as e:
    print(f"Warning during XML-RPC setup: {e}")
PYEOF

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox http://localhost:8069/web &"
    sleep 5
fi

# Focus and maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot "/tmp/bulk_import_initial.png" || true

echo "=== Task Setup Complete ==="