#!/bin/bash
echo "=== Setting up deregister_civilian_weapon task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure MySQL is ready
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec opencad-db mysqladmin ping -h localhost -u root -prootpass >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 2. Setup Data: Ensure Civilian Exists
echo "Setting up civilian data..."
CIV_NAME="Michael DeSanta"
# Check if exists
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='${CIV_NAME}' LIMIT 1")

if [ -z "$CIV_ID" ]; then
    echo "Creating civilian ${CIV_NAME}..."
    opencad_db_query "INSERT INTO ncic_names (name, dob, address, gender, race, hair_color, build, user_id) VALUES ('${CIV_NAME}', '1965-09-21', 'Rockford Hills', 'Male', 'White', 'Black', 'Average', 2);"
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='${CIV_NAME}' LIMIT 1")
fi

echo "Civilian ID: $CIV_ID"

# 3. Setup Data: Reset Weapons
# Remove existing weapons with these serials to ensure clean state
opencad_db_query "DELETE FROM ncic_weapons WHERE serial_number IN ('DSL-882', 'KEE-456')"

# Insert Target Weapon (To be deleted)
opencad_db_query "INSERT INTO ncic_weapons (name_id, weapon_type, weapon_name, serial_number, wstatus) VALUES ($CIV_ID, 'Pistol', 'Combat Pistol', 'DSL-882', 'Valid')"

# Insert Safe Weapon (To be kept)
opencad_db_query "INSERT INTO ncic_weapons (name_id, weapon_type, weapon_name, serial_number, wstatus) VALUES ($CIV_ID, 'Shotgun', 'Pump Shotgun', 'KEE-456', 'Valid')"

# 4. Record Initial State
INITIAL_WEAPON_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_weapons WHERE name_id=$CIV_ID")