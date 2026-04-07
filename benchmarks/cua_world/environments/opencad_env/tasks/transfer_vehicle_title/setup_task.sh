#!/bin/bash
echo "=== Setting up transfer_vehicle_title task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for database availability
echo "Waiting for database..."
for i in {1..30}; do
    if docker exec opencad-db mysqladmin ping -h localhost -u root -prootpass 2>/dev/null; then
        break
    fi
    sleep 1
done

# 2. Prepare Data: Create Civilians and Vehicle via Python
# We use Python to handle ID retrieval dynamically
cat << 'EOF' > /tmp/setup_data.py
import pymysql
import sys

def get_connection():
    return pymysql.connect(
        host='127.0.0.1',
        user='opencad',
        password='opencadpass',
        database='opencad',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )

conn = get_connection()
try:
    with conn.cursor() as cursor:
        # Clean up potential previous run artifacts
        cursor.execute("DELETE FROM ncic_plates WHERE plate = 'XCAV8R'")
        cursor.execute("DELETE FROM ncic_names WHERE name IN ('John Driller', 'Sarah SiteLead')")
        
        # Create Old Owner (John Driller)
        # Assuming user_id 2 (Admin) manages these civs
        sql_civ = "INSERT INTO ncic_names (name, dob, address, gender, race, hair_color, build, user_id) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"
        cursor.execute(sql_civ, ('John Driller', '1980-05-15', '12 Quarry Rd', 'Male', 'White', 'Brown', 'Medium', 2))
        john_id = cursor.lastrowid
        
        # Create New Owner (Sarah SiteLead)
        cursor.execute(sql_civ, ('Sarah SiteLead', '1985-08-22', '44 Admin Ln', 'Female', 'White', 'Blonde', 'Slim', 2))
        sarah_id = cursor.lastrowid
        
        # Create Vehicle assigned to John
        # Table ncic_plates: plate, brand, model, color, year, name_id (owner), user_id
        sql_veh = "INSERT INTO ncic_plates (plate, brand, model, color, year, name_id, user_id, status) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)"
        cursor.execute(sql_veh, ('XCAV8R', 'Vapid', 'Sandking', 'Orange', '2022', john_id, 2, 'Valid'))
        veh_id = cursor.lastrowid
        
        conn.commit()
        
        print(f"Setup Complete: JohnID={john_id}, SarahID={sarah_id}, VehID={veh_id}")
        
        # Save IDs to file for verification
        with open('/tmp/initial_vehicle_id.txt', 'w') as f:
            f.write(str(veh_id))
        with open('/tmp/john_id.txt', 'w') as f:
            f.write(str(john_id))
        with open('/tmp/sarah_id.txt', 'w') as f:
            f.write(str(sarah_id))

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
finally:
    conn.close()
EOF

# Execute data setup inside the container (if pymysql is not in host, use docker exec)
# But here we assume we are running in the environment which has python and mysql access
# If running on the host 'ga' user which has access to the docker network ports mapped:
# The docker-compose maps 3306:3306, so localhost works.
# But we need pymysql. If not present, we use docker exec python approach or SQL.
# The env install script installed pymysql.

python3 /tmp/setup_data.py

# 3. Launch Application
# Remove Firefox profile locks
rm -f /home/ga/.mozilla/firefox/default-release/lock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2

DISPLAY=:1 firefox "http://localhost/login.php" &
sleep 8

# Maximize
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="