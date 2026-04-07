#!/bin/bash
# Setup script for pos_session_cash_closing_variance task
# Creates a POS session with $100 opening cash + $350 in sales = $450 theoretical.
# Provides a physical count of $445 (shortage of $5).

echo "=== Setting up POS Cash Closing Variance Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Wait for Odoo
echo "Waiting for Odoo XML-RPC..."
for i in $(seq 1 30); do
    curl -s "http://localhost:8069/xmlrpc/2/common" -o /dev/null 2>/dev/null && break
    sleep 3
done

# 3. Python script to set up POS data
python3 << 'PYEOF'
import xmlrpc.client
import sys
import time

URL = 'http://localhost:8069'
DB = 'odoo_demo'
USERNAME = 'admin@example.com'
PASSWORD = 'admin'

def connect():
    try:
        common = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/common')
        uid = common.authenticate(DB, USERNAME, PASSWORD, {})
        models = xmlrpc.client.ServerProxy(f'{URL}/xmlrpc/2/object')
        return uid, models
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

uid, models = connect()

def execute(model, method, args=None, kwargs=None):
    return models.execute_kw(DB, uid, PASSWORD, model, method, args or [], kwargs or {})

# --- Ensure POS Module is Installed ---
# (Usually installed in odoo_demo, but good to check)
# We assume it's there or we'd need to install it which takes time.

# --- Get 'Main Shop' Config ---
configs = execute('pos.config', 'search_read', 
    [[['name', '=', 'Main Shop']]], 
    {'fields': ['id', 'name', 'journal_id']})

if not configs:
    # Create if missing
    journal_id = execute('account.journal', 'search', [[['type', '=', 'sale']]], {'limit': 1})[0]
    config_id = execute('pos.config', 'create', [{
        'name': 'Main Shop',
        'journal_id': journal_id
    }])
    print(f"Created POS Config: Main Shop (id={config_id})")
else:
    config_id = configs[0]['id']
    print(f"Using POS Config: Main Shop (id={config_id})")

# --- Ensure no existing open sessions for this config ---
# Close any open sessions to start fresh
open_sessions = execute('pos.session', 'search', 
    [[['config_id', '=', config_id], ['state', '!=', 'closed']]])

if open_sessions:
    print(f"Closing {len(open_sessions)} stale sessions...")
    for sess_id in open_sessions:
        # Try to close/rescue via python? Hard to do cleanly without complex logic.
        # Simpler: just set state to closed via write (dirty hack for setup only)
        # In a real scenario, we'd use the action_pos_session_closing_control, but that's complex via API.
        # We will just ignore them and create a new config if needed, or try to close.
        # Let's try to 'rescue' them to closed state forcibly for setup speed.
        execute('pos.session', 'write', [[sess_id], {'state': 'closed'}])

# --- Start New Session ---
# 1. Create Session
session_id = execute('pos.session', 'create', [{
    'config_id': config_id,
    'user_id': uid,
    'start_at': time.strftime('%Y-%m-%d %H:%M:%S')
}])
print(f"Created Session ID: {session_id}")

# 2. Set Opening Cash ($100)
# We need the cash journal associated with this POS
pos_config = execute('pos.config', 'read', [config_id], ['payment_method_ids'])[0]
payment_method_ids = pos_config['payment_method_ids']
cash_method = execute('pos.payment.method', 'search_read', 
    [[['id', 'in', payment_method_ids], ['is_cash_count', '=', True]]], 
    {'fields': ['id', 'name'], 'limit': 1})

if not cash_method:
    print("Error: No cash payment method found for Main Shop")
    sys.exit(1)

cash_method_id = cash_method[0]['id']

# Set opening balance (this is usually done via bank statement in older Odoo or cash box in newer)
# In Odoo 16/17, we can set 'state' to 'opened' and update cash_register_balance_start
execute('pos.session', 'write', [[session_id], {
    'state': 'opened',
    'cash_register_balance_start': 100.0
}])

# 3. Create a dummy order to generate sales ($350)
# Create a product "Test Sale"
product_id = execute('product.product', 'create', [{
    'name': 'General Item',
    'list_price': 350.0,
    'available_in_pos': True
}])

order_id = execute('pos.order', 'create', [{
    'session_id': session_id,
    'lines': [[0, 0, {
        'product_id': product_id,
        'qty': 1,
        'price_unit': 350.0,
        'price_subtotal': 350.0,
        'price_subtotal_incl': 350.0
    }]],
    'amount_total': 350.0,
    'amount_paid': 350.0,
    'amount_return': 0.0,
    'state': 'paid',  # Immediately paid
    'date_order': time.strftime('%Y-%m-%d %H:%M:%S')
}])

# Add payment
execute('pos.make.payment', 'create', [{
    'pos_order_id': order_id,
    'amount': 350.0,
    'payment_method_id': cash_method_id
}])

print(f"Created Order {order_id} for $350.00")

# Save Session ID for verification
with open('/tmp/target_session_id.txt', 'w') as f:
    f.write(str(session_id))

PYEOF

# 4. Create Physical Count File
cat > /home/ga/Desktop/cash_count.txt << 'EOF'
End of Day Cash Count
Date: Today
Register: Main Shop

---------------------------
Bills & Coins Total: $445.00
---------------------------

Note: Please close the session using this exact amount.
Verify any variances.
EOF

# 5. Launch Firefox to POS Dashboard
echo "Launching Firefox..."
# Check if firefox running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8069/web#action=point_of_sale.action_client_pos_menu' &"
else
    # Reload or open new tab? Just ensuring it's there.
    # We leave it to the agent to navigate.
    echo "Firefox already running."
fi

# 6. Maximize
sleep 5
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="