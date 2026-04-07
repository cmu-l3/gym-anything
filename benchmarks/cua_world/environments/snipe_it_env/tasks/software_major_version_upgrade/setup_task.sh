#!/bin/bash
echo "=== Setting up software_major_version_upgrade task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Database Dependencies
echo "--- Injecting prerequisites (Category, Manufacturers) ---"

# Create Category
snipeit_db_query "INSERT INTO categories (name, category_type, require_acceptance, use_default_eula, created_at, updated_at) VALUES ('Graphics Software', 'license', 0, 0, NOW(), NOW())" 2>/dev/null || true
CAT_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Graphics Software' AND category_type='license' LIMIT 1" | tr -d '[:space:]')

# Create Manufacturers
snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('Autodesk', NOW(), NOW())" 2>/dev/null || true
MAN_AUTO_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Autodesk' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO manufacturers (name, created_at, updated_at) VALUES ('Maxon', NOW(), NOW())" 2>/dev/null || true
MAN_MAXON_ID=$(snipeit_db_query "SELECT id FROM manufacturers WHERE name='Maxon' LIMIT 1" | tr -d '[:space:]')

echo "Category ID: $CAT_ID | Autodesk ID: $MAN_AUTO_ID | Maxon ID: $MAN_MAXON_ID"

# 2. Prepare Users
echo "--- Injecting test users ---"
snipeit_db_query "INSERT INTO users (first_name, last_name, username, password, permissions, activated, created_at) VALUES ('Alex', 'Rivet', 'arivet', 'pass123', '{\"user\":1}', 1, NOW())" 2>/dev/null || true
USER1_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='arivet' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO users (first_name, last_name, username, password, permissions, activated, created_at) VALUES ('Beth', 'Shader', 'bshader', 'pass123', '{\"user\":1}', 1, NOW())" 2>/dev/null || true
USER2_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='bshader' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO users (first_name, last_name, username, password, permissions, activated, created_at) VALUES ('Carl', 'Vertex', 'cvertex', 'pass123', '{\"user\":1}', 1, NOW())" 2>/dev/null || true
USER3_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='cvertex' LIMIT 1" | tr -d '[:space:]')

snipeit_db_query "INSERT INTO users (first_name, last_name, username, password, permissions, activated, created_at) VALUES ('Dana', 'Spline', 'dspline', 'pass123', '{\"user\":1}', 1, NOW())" 2>/dev/null || true
USER4_ID=$(snipeit_db_query "SELECT id FROM users WHERE username='dspline' LIMIT 1" | tr -d '[:space:]')

# 3. Create Legacy Licenses using API (to ensure seats are created)
echo "--- Injecting legacy licenses ---"
MAYA_RESP=$(snipeit_api POST "licenses" "{\"name\":\"Autodesk Maya 2023\",\"seats\":15,\"manufacturer_id\":$MAN_AUTO_ID,\"category_id\":$CAT_ID,\"product_key\":\"MAYA-2023-LEGACY\",\"purchase_cost\":12000}")
MAYA_ID=$(snipeit_db_query "SELECT id FROM licenses WHERE name='Autodesk Maya 2023' LIMIT 1" | tr -d '[:space:]')

C4D_RESP=$(snipeit_api POST "licenses" "{\"name\":\"Maxon Cinema 4D R25\",\"seats\":10,\"manufacturer_id\":$MAN_MAXON_ID,\"category_id\":$CAT_ID,\"product_key\":\"C4D-R25-LEGACY\",\"purchase_cost\":8000}")
C4D_ID=$(snipeit_db_query "SELECT id FROM licenses WHERE name='Maxon Cinema 4D R25' LIMIT 1" | tr -d '[:space:]')

echo "Legacy Maya ID: $MAYA_ID | Legacy C4D ID: $C4D_ID"

# 4. Check out seats (raw SQL is safest for direct state forcing)
echo "--- Assigning legacy seats to users ---"

# Assign Maya to User 1 & 2
SEAT1=$(snipeit_db_query "SELECT id FROM license_seats WHERE license_id=$MAYA_ID AND assigned_to IS NULL LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE license_seats SET assigned_to=$USER1_ID, updated_at=NOW() WHERE id=$SEAT1"
SEAT2=$(snipeit_db_query "SELECT id FROM license_seats WHERE license_id=$MAYA_ID AND assigned_to IS NULL LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE license_seats SET assigned_to=$USER2_ID, updated_at=NOW() WHERE id=$SEAT2"

# Assign C4D to User 3 & 4
SEAT3=$(snipeit_db_query "SELECT id FROM license_seats WHERE license_id=$C4D_ID AND assigned_to IS NULL LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE license_seats SET assigned_to=$USER3_ID, updated_at=NOW() WHERE id=$SEAT3"
SEAT4=$(snipeit_db_query "SELECT id FROM license_seats WHERE license_id=$C4D_ID AND assigned_to IS NULL LIMIT 1" | tr -d '[:space:]')
snipeit_db_query "UPDATE license_seats SET assigned_to=$USER4_ID, updated_at=NOW() WHERE id=$SEAT4"

# 5. Record Baseline Data for Export/Verifier
echo "--- Recording baseline data ---"
echo "$USER1_ID,$USER2_ID" > /tmp/target_maya_users.txt
echo "$USER3_ID,$USER4_ID" > /tmp/target_c4d_users.txt
echo "$MAYA_ID" > /tmp/legacy_maya_id.txt
echo "$C4D_ID" > /tmp/legacy_c4d_id.txt

# Store start time
date +%s > /tmp/task_start_time.txt

# 6. Prepare UI
echo "--- Launching UI ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/licenses"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="