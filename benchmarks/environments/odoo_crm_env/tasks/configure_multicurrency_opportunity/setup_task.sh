#!/bin/bash
set -e
echo "=== Setting up configure_multicurrency_opportunity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

echo "Resetting environment state..."
# Python script to reset state:
# 1. Deactivate EUR currency
# 2. Delete the target opportunity if it exists
# 3. Delete the target partner if it exists
python3 - <<'PYEOF'
import xmlrpc.client
import ssl

# Ignore SSL verification for local self-signed certs if needed
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = "http://localhost:8069"
db = "odoodb"
username = "admin"
password = "admin"

try:
    common = xmlrpc.client.ServerProxy('{}/xmlrpc/2/common'.format(url), context=ctx)
    uid = common.authenticate(db, username, password, {})
    models = xmlrpc.client.ServerProxy('{}/xmlrpc/2/object'.format(url), context=ctx)

    # 1. Deactivate EUR currency
    # Find EUR
    eur_ids = models.execute_kw(db, uid, password, 'res.currency', 'search', [[['name', '=', 'EUR']]])
    if eur_ids:
        models.execute_kw(db, uid, password, 'res.currency', 'write', [eur_ids, {'active': False}])
        print(f"Deactivated EUR currency (IDs: {eur_ids})")

    # 2. Delete target opportunity
    opp_name = "Munich Warehouse Solar Installation"
    opp_ids = models.execute_kw(db, uid, password, 'crm.lead', 'search', [[['name', '=', opp_name]]])
    if opp_ids:
        models.execute_kw(db, uid, password, 'crm.lead', 'unlink', [opp_ids])
        print(f"Deleted existing opportunities: {opp_ids}")

    # 3. Delete target partner
    partner_name = "Bavaria Logistics GmbH"
    partner_ids = models.execute_kw(db, uid, password, 'res.partner', 'search', [[['name', '=', partner_name]]])
    if partner_ids:
        models.execute_kw(db, uid, password, 'res.partner', 'unlink', [partner_ids])
        print(f"Deleted existing partners: {partner_ids}")

    # Attempt to disable multi-currency group (user setting) if possible
    # This is complex in Odoo as it involves groups, but deactivating the currency is the main functional check
    
except Exception as e:
    print(f"Setup Error: {e}")
    exit(1)
PYEOF

# Ensure Firefox is open and logged in
ensure_odoo_logged_in "http://localhost:8069/web"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="