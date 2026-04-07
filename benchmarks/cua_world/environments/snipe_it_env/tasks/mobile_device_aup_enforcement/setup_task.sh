#!/bin/bash
echo "=== Setting up mobile_device_aup_enforcement task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Create the AUP Legal Document
echo "--- Creating Legal AUP File ---"
mkdir -p /home/ga/Documents/Legal
cat > /home/ga/Documents/Legal/2026_Mobile_AUP.txt << 'EOF'
2026 Mobile Device Acceptable Use Policy

By accepting this mobile device (laptop, tablet, or smartphone), you agree to the following corporate terms and conditions:

1. OWNERSHIP: The device remains the exclusive property of the company and must be surrendered immediately upon termination of employment or upon request by the IT department.
2. UNAUTHORIZED SOFTWARE: You will not install unauthorized, unlicensed, or malicious software. 
3. REPORTING: You will immediately report to the Help Desk if the device is lost, stolen, or compromised.
4. SECURITY: The device must remain encrypted and password protected at all times. Do not bypass MDM (Mobile Device Management) controls.
5. DATA HANDLING: No highly classified client data may be stored locally on the device's hard drive without written explicit consent from the Legal team.

I acknowledge that I have read and agree to these terms.
EOF
chown -R ga:ga /home/ga/Documents/Legal

# 2. Get required IDs from Snipe-IT database
SL_READY_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Ready to Deploy' LIMIT 1" | tr -d '[:space:]')
CAT_LAPTOP_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
CAT_TABLET_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Tablets' LIMIT 1" | tr -d '[:space:]')
CAT_DESKTOP_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Desktops' LIMIT 1" | tr -d '[:space:]')

# Reset categories to ensure clean baseline (require_accept = 0, eula_text = null)
echo "--- Resetting Category Configurations ---"
snipeit_db_query "UPDATE categories SET require_accept=0, eula_text=NULL WHERE name IN ('Laptops', 'Tablets', 'Desktops')"

# 3. Create Models if they don't exist, or get existing ones
MDL_LAPTOP_ID=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_LAPTOP_ID LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_LAPTOP_ID" ]; then
    MDL_LAPTOP_ID=$(snipeit_db_query "INSERT INTO models (name, category_id, created_at, updated_at) VALUES ('MacBook Pro 14', $CAT_LAPTOP_ID, NOW(), NOW()); SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi

MDL_TABLET_ID=$(snipeit_db_query "SELECT id FROM models WHERE category_id=$CAT_TABLET_ID LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_TABLET_ID" ]; then
    MDL_TABLET_ID=$(snipeit_db_query "INSERT INTO models (name, category_id, created_at, updated_at) VALUES ('iPad Pro 11-inch', $CAT_TABLET_ID, NOW(), NOW()); SELECT LAST_INSERT_ID();" | tr -d '[:space:]')
fi

# 4. Inject target user (David Thorne)
echo "--- Injecting User ---"
snipeit_db_query "DELETE FROM users WHERE username='dthorne'" 2>/dev/null || true
snipeit_api POST "users" "{\"first_name\":\"David\",\"last_name\":\"Thorne\",\"username\":\"dthorne\",\"email\":\"dthorne@example.com\",\"password\":\"password123\",\"password_confirmation\":\"password123\"}"
sleep 1

# 5. Inject target assets
echo "--- Injecting Assets ---"
snipeit_db_query "DELETE FROM assets WHERE asset_tag IN ('LT-2026-001', 'TAB-2026-001')" 2>/dev/null || true
snipeit_api POST "hardware" "{\"asset_tag\":\"LT-2026-001\",\"name\":\"David Thorne Laptop\",\"model_id\":$MDL_LAPTOP_ID,\"status_id\":$SL_READY_ID,\"serial\":\"MBP-LT-001\"}"
snipeit_api POST "hardware" "{\"asset_tag\":\"TAB-2026-001\",\"name\":\"David Thorne Tablet\",\"model_id\":$MDL_TABLET_ID,\"status_id\":$SL_READY_ID,\"serial\":\"IPAD-TAB-001\"}"
sleep 1

# 6. Ensure Firefox is running and on Snipe-IT
echo "--- Opening Application ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3

# Take initial screenshot
take_screenshot /tmp/aup_enforcement_initial.png

echo "=== mobile_device_aup_enforcement task setup complete ==="