#!/bin/bash
echo "=== Setting up corporate_rebranding_system_config task ==="
source /workspace/scripts/task_utils.sh

# 1. Setup User Jane Smith
JANE_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='jsmith' AND deleted_at IS NULL" | tr -d '[:space:]')
if [ -z "$JANE_ID" ]; then
    echo "  Creating user Jane Smith..."
    snipeit_db_query "INSERT INTO users (first_name, last_name, username, email, password, activated, created_at, updated_at) VALUES ('Jane', 'Smith', 'jsmith', 'jsmith@acmeglobal.com', 'dummy_hash', 1, NOW(), NOW())"
else
    echo "  Resetting user Jane Smith..."
    snipeit_db_query "UPDATE users SET email='jsmith@acmeglobal.com' WHERE id=$JANE_ID"
fi

# 2. Setup Category & Model for Hardware provisioning
CAT_LAPTOP=$(snipeit_db_query "SELECT id FROM categories WHERE name='Laptops' LIMIT 1" | tr -d '[:space:]')
MAN_DELL=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Dell' LIMIT 1" | tr -d '[:space:]')
MOD_XPS=$(snipeit_db_query "SELECT id FROM models WHERE name='XPS 15' LIMIT 1" | tr -d '[:space:]')

if [ -z "$MOD_XPS" ]; then
    echo "  Creating XPS 15 model..."
    if [ -n "$CAT_LAPTOP" ] && [ -n "$MAN_DELL" ]; then
        snipeit_db_query "INSERT INTO models (name, category_id, manufacturer_id, created_at, updated_at) VALUES ('XPS 15', $CAT_LAPTOP, $MAN_DELL, NOW(), NOW())"
    fi
fi

# 3. Reset Settings to default starting state
echo "  Resetting global settings..."
snipeit_db_query "UPDATE settings SET 
    site_name='Snipe-IT Asset Management', 
    default_currency='USD', 
    email_domain='acmeglobal.com', 
    default_eula_text=NULL, 
    support_email=NULL, 
    support_phone=NULL, 
    support_url=NULL, 
    auto_increment_prefix='ASSET-', 
    auto_increment_assets=1, 
    alert_email=NULL 
WHERE id=1"

# 4. Remove any existing assets that might conflict with the target state (NEX-)
echo "  Cleaning up any conflicting NEX- assets..."
snipeit_db_query "DELETE FROM assets WHERE asset_tag LIKE 'NEX-%'"

# 5. Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 6. Open Firefox and setup the window view
echo "  Launching browser..."
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000"
sleep 3
take_screenshot /tmp/rebrand_initial.png

echo "=== Setup complete ==="