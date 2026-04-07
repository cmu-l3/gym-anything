#!/bin/bash
set -e
echo "=== Setting up consumable_supply_audit task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------
# 1. Database Setup: Create required categories
# ---------------------------------------------------------------
echo "--- Creating consumable categories via DB ---"
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Printer Supplies', 'consumable', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Cables', 'consumable', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Adapters', 'consumable', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Storage Media', 'consumable', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO categories (name, category_type, created_at, updated_at) VALUES ('Batteries', 'consumable', NOW(), NOW())"

CAT_PRINTER=$(snipeit_db_query "SELECT id FROM categories WHERE name='Printer Supplies' LIMIT 1" | tr -d '[:space:]')
CAT_CABLES=$(snipeit_db_query "SELECT id FROM categories WHERE name='Cables' LIMIT 1" | tr -d '[:space:]')
CAT_ADAPTERS=$(snipeit_db_query "SELECT id FROM categories WHERE name='Adapters' LIMIT 1" | tr -d '[:space:]')
CAT_STORAGE=$(snipeit_db_query "SELECT id FROM categories WHERE name='Storage Media' LIMIT 1" | tr -d '[:space:]')
CAT_BATTERIES=$(snipeit_db_query "SELECT id FROM categories WHERE name='Batteries' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 2. Database Setup: Create additional manufacturers
# ---------------------------------------------------------------
echo "--- Creating manufacturers via DB ---"
snipeit_db_query "INSERT IGNORE INTO manufacturers (name, created_at, updated_at) VALUES ('StarTech', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO manufacturers (name, created_at, updated_at) VALUES ('Logitech', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO manufacturers (name, created_at, updated_at) VALUES ('SanDisk', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO manufacturers (name, created_at, updated_at) VALUES ('Energizer', NOW(), NOW())"
snipeit_db_query "INSERT IGNORE INTO manufacturers (name, created_at, updated_at) VALUES ('HP', NOW(), NOW())"

MFG_STARTECH=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='StarTech' LIMIT 1" | tr -d '[:space:]')
MFG_LOGITECH=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Logitech' LIMIT 1" | tr -d '[:space:]')
MFG_SANDISK=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='SanDisk' LIMIT 1" | tr -d '[:space:]')
MFG_ENERGIZER=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Energizer' LIMIT 1" | tr -d '[:space:]')
MFG_HP=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='HP' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 3. Database Setup: Create existing consumables (to be updated)
# ---------------------------------------------------------------
echo "--- Creating existing consumables via DB ---"
snipeit_db_query "DELETE FROM consumables WHERE name IN ('USB-A Flash Drive 32GB', 'AA Batteries (Pack of 24)')"

snipeit_db_query "INSERT INTO consumables (name, category_id, manufacturer_id, qty, min_amt, purchase_cost, model_number, order_number, created_at, updated_at) VALUES ('USB-A Flash Drive 32GB', $CAT_STORAGE, $MFG_SANDISK, 45, 5, 12.99, 'SDCZ48-032G', 'PO-2024-0501', NOW(), NOW())"
FLASH_ID=$(snipeit_db_query "SELECT id FROM consumables WHERE name='USB-A Flash Drive 32GB' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO consumables (name, category_id, manufacturer_id, qty, min_amt, purchase_cost, model_number, order_number, created_at, updated_at) VALUES ('AA Batteries (Pack of 24)', $CAT_BATTERIES, $MFG_ENERGIZER, 60, 10, 16.49, 'E91BP-24', 'PO-2024-0502', NOW(), NOW())"
BATTERY_ID=$(snipeit_db_query "SELECT id FROM consumables WHERE name='AA Batteries (Pack of 24)' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 4. Database Setup: Create users
# ---------------------------------------------------------------
echo "--- Verifying/Creating users via DB ---"
snipeit_db_query "INSERT IGNORE INTO users (first_name, last_name, username, email, password, activated, created_at, updated_at) VALUES ('John', 'Smith', 'jsmith', 'jsmith@university.edu', 'hash', 1, NOW(), NOW())"
JSMITH_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='jsmith' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT IGNORE INTO users (first_name, last_name, username, email, password, activated, created_at, updated_at) VALUES ('Alice', 'Johnson', 'ajohnson', 'ajohnson@university.edu', 'hash', 1, NOW(), NOW())"
AJOHNSON_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='ajohnson' LIMIT 1" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 5. Save state for verification
# ---------------------------------------------------------------
echo "--- Saving initial state ---"
INITIAL_CONSUMABLE_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM consumables WHERE deleted_at IS NULL" | tr -d '[:space:]')
echo "$INITIAL_CONSUMABLE_COUNT" > /tmp/initial_consumable_count.txt
echo "$JSMITH_ID" > /tmp/jsmith_id.txt
echo "$AJOHNSON_ID" > /tmp/ajohnson_id.txt
echo "$FLASH_ID" > /tmp/flash_drive_id.txt
echo "$BATTERY_ID" > /tmp/battery_id.txt

# Record IDs of newly created items if any exist (to avoid false positives if pre-seeded)
snipeit_db_query "SELECT id FROM consumables WHERE deleted_at IS NULL" > /tmp/initial_consumable_ids.txt

# ---------------------------------------------------------------
# 6. Open Firefox on Snipe-IT
# ---------------------------------------------------------------
echo "--- Setting up Firefox ---"
ensure_firefox_snipeit
sleep 3
navigate_firefox_to "http://localhost:8000/consumables"
sleep 3
focus_firefox

take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="