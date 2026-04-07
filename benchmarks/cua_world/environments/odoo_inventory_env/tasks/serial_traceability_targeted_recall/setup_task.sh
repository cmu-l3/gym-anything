#!/bin/bash
# Setup script for Serial Traceability Targeted Recall
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
    echo "Starting docker-compose..."
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

date +%s > /tmp/task_start_timestamp
rm -f /tmp/serial_traceability_result.json

if [ -z "$PG_CONTAINER" ]; then
    echo "FATAL: No PostgreSQL container available. Skipping setup."
    exit 1
fi

echo "Checking database usability..."
DB_USABLE=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc "SELECT 1" 2>/dev/null | tr -d ' \n')

if [ "$DB_USABLE" != "1" ]; then
    echo "Database '${ODOO_DB}' not usable. Recreating..."
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS ${ODOO_DB}" 2>/dev/null || true
    sleep 2
    docker exec "$PG_CONTAINER" psql -U odoo -d postgres -c "CREATE DATABASE ${ODOO_DB} OWNER odoo ENCODING 'UTF8'" 2>/dev/null || true
    sleep 2

    echo "Initializing Odoo modules (this may take a few minutes)..."
    docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
        -i base,stock,sale_management,purchase \
        --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -20 || true

    docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
    
    docker restart odoo-web 2>/dev/null || true
    sleep 15
else
    # Check if modules are installed
    MODULES_INSTALLED=$(docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -tAc \
        "SELECT COUNT(*) FROM ir_module_module WHERE name='base' AND state='installed'" 2>/dev/null | tr -d ' \n')
    if [ "$MODULES_INSTALLED" != "1" ] && [ "$MODULES_INSTALLED" != "" ]; then
        docker exec odoo-web odoo -c /etc/odoo/odoo.conf -d "${ODOO_DB}" \
            -i base,stock,sale_management,purchase \
            --load-language=en_US --without-demo=False --stop-after-init 2>&1 | tail -10 || true
        docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "UPDATE res_users SET login='admin' WHERE id=2" 2>/dev/null || true
        docker restart odoo-web 2>/dev/null || true
        sleep 15
    fi
fi

# Ensure Traceability features are enabled in settings
docker exec "$PG_CONTAINER" psql -U odoo -d "${ODOO_DB}" -c "
UPDATE res_config_settings SET group_stock_production_lot = true;
UPDATE res_groups SET name = 'group_stock_production_lot' WHERE id IN (SELECT gid FROM res_groups_users_rel);
" 2>/dev/null || true

echo "Injecting task data via Odoo ORM..."
# Use Odoo shell to safely inject complex serialized inventory data
cat << 'EOF' > /tmp/setup_traceability_data.py
import logging
env = env(user=1)

try:
    # Enable lots and serial numbers globally
    group_lot = env.ref('stock.group_stock_production_lot')
    env.user.write({'groups_id': [(4, group_lot.id)]})
    
    # 1. Create Product
    product = env['product.product'].search([('default_code', '=', 'MED-CM-PRO')], limit=1)
    if not product:
        product = env['product.product'].create({
            'name': 'CardioMon Pro Patient Monitor',
            'default_code': 'MED-CM-PRO',
            'type': 'product',
            'tracking': 'serial',
            'list_price': 4500.0,
        })
    else:
        product.write({'tracking': 'serial'})

    # 2. Base Locations
    supplier_loc = env.ref('stock.stock_location_suppliers')
    stock_loc = env.ref('stock.stock_location_stock')
    customer_loc = env.ref('stock.stock_location_customers')
    picking_type_in = env['stock.picking.type'].search([('code', '=', 'incoming'), ('company_id', '=', env.company.id)], limit=1)
    picking_type_out = env['stock.picking.type'].search([('code', '=', 'outgoing'), ('company_id', '=', env.company.id)], limit=1)

    # 3. Receipt 1 (The Batch with the defect)
    receipt1 = env['stock.picking'].create({
        'picking_type_id': picking_type_in.id,
        'location_id': supplier_loc.id,
        'location_dest_id': stock_loc.id,
        'origin': 'PO-MedSupply-011',
    })
    move1 = env['stock.move'].create({
        'name': product.name,
        'product_id': product.id,
        'product_uom_qty': 4,
        'product_uom': product.uom_id.id,
        'picking_id': receipt1.id,
        'location_id': supplier_loc.id,
        'location_dest_id': stock_loc.id,
    })
    receipt1.action_confirm()
    receipt1.action_assign()
    
    sns_bad_batch = ['CM-2024-089', 'CM-2024-090', 'CM-2024-091', 'CM-2024-092']
    for sn in sns_bad_batch:
        lot = env['stock.lot'].create({'name': sn, 'product_id': product.id, 'company_id': env.company.id})
        env['stock.move.line'].create({
            'move_id': move1.id,
            'picking_id': receipt1.id,
            'product_id': product.id,
            'location_id': supplier_loc.id,
            'location_dest_id': stock_loc.id,
            'qty_done': 1,
            'lot_id': lot.id,
        })
    receipt1.button_validate()

    # 4. Delivery 1 (Shipped out to hospital)
    delivery1 = env['stock.picking'].create({
        'picking_type_id': picking_type_out.id,
        'location_id': stock_loc.id,
        'location_dest_id': customer_loc.id,
        'origin': 'SO-Hospital-001',
    })
    move_out = env['stock.move'].create({
        'name': product.name,
        'product_id': product.id,
        'product_uom_qty': 2,
        'product_uom': product.uom_id.id,
        'picking_id': delivery1.id,
        'location_id': stock_loc.id,
        'location_dest_id': customer_loc.id,
    })
    delivery1.action_confirm()
    delivery1.action_assign()
    
    # Send out the reported defective unit (089) and one sibling (091)
    for sn in ['CM-2024-089', 'CM-2024-091']:
        lot = env['stock.lot'].search([('name', '=', sn), ('product_id', '=', product.id)], limit=1)
        env['stock.move.line'].create({
            'move_id': move_out.id,
            'picking_id': delivery1.id,
            'product_id': product.id,
            'location_id': stock_loc.id,
            'location_dest_id': customer_loc.id,
            'qty_done': 1,
            'lot_id': lot.id,
        })
    delivery1.button_validate()

    # 5. Receipt 2 (The Clean Batch)
    receipt2 = env['stock.picking'].create({
        'picking_type_id': picking_type_in.id,
        'location_id': supplier_loc.id,
        'location_dest_id': stock_loc.id,
        'origin': 'PO-MedSupply-012',
    })
    move2 = env['stock.move'].create({
        'name': product.name,
        'product_id': product.id,
        'product_uom_qty': 3,
        'product_uom': product.uom_id.id,
        'picking_id': receipt2.id,
        'location_id': supplier_loc.id,
        'location_dest_id': stock_loc.id,
    })
    receipt2.action_confirm()
    receipt2.action_assign()
    
    sns_good_batch = ['CM-2024-093', 'CM-2024-094', 'CM-2024-095']
    for sn in sns_good_batch:
        lot = env['stock.lot'].create({'name': sn, 'product_id': product.id, 'company_id': env.company.id})
        env['stock.move.line'].create({
            'move_id': move2.id,
            'picking_id': receipt2.id,
            'product_id': product.id,
            'location_id': supplier_loc.id,
            'location_dest_id': stock_loc.id,
            'qty_done': 1,
            'lot_id': lot.id,
        })
    receipt2.button_validate()
    
    env.cr.commit()
    print("DATA_INJECTION_SUCCESS")
except Exception as e:
    print(f"DATA_INJECTION_FAILED: {str(e)}")
    env.cr.rollback()
EOF

docker cp /tmp/setup_traceability_data.py odoo-web:/tmp/setup_traceability_data.py
docker exec odoo-web odoo shell -c /etc/odoo/odoo.conf -d "${ODOO_DB}" --no-http < /tmp/setup_traceability_data.py > /tmp/odoo_injection.log 2>&1

take_screenshot "/tmp/task_initial_state.png" || true

echo "=== Setup complete ==="