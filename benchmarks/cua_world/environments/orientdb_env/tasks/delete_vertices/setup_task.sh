#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up delete_vertices task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# Ensure Firefox is closed initially to prevent profile locks
kill_firefox

# Verify the three target hotels exist before the task begins
# If not, insert them to ensure the task is solvable
for HOTEL_NAME in "Copacabana Palace" "Park Hyatt Tokyo" "Four Seasons Sydney"; do
    EXISTS=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels WHERE Name = '${HOTEL_NAME}'" | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
    
    if [ "$EXISTS" = "0" ]; then
        echo "WARNING: Hotel '${HOTEL_NAME}' not found! Inserting..."
        if [ "$HOTEL_NAME" = "Copacabana Palace" ]; then
            orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Copacabana Palace', Type='Historic', Phone='+55-21-2548-7070', Latitude=-22.9683, Longitude=-43.1842, Street='Av. Atlantica 1702', City='Rio de Janeiro', Country='Brazil', Stars=5"
        elif [ "$HOTEL_NAME" = "Park Hyatt Tokyo" ]; then
            orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Park Hyatt Tokyo', Type='Luxury', Phone='+81-3-5322-1234', Latitude=35.6858, Longitude=139.6909, Street='3-7-1-2 Nishi Shinjuku', City='Tokyo', Country='Japan', Stars=5"
        elif [ "$HOTEL_NAME" = "Four Seasons Sydney" ]; then
            orientdb_sql "demodb" "INSERT INTO Hotels SET Name='Four Seasons Sydney', Type='Luxury', Phone='+61-2-9250-3100', Latitude=-33.8611, Longitude=151.2112, Street='199 George Street', City='Sydney', Country='Australia', Stars=5"
        fi
        echo "Inserted '${HOTEL_NAME}'"
    else
        echo "Hotel '${HOTEL_NAME}' exists."
    fi
done

# Record initial hotel count
INITIAL_HOTEL_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")
echo "$INITIAL_HOTEL_COUNT" > /tmp/initial_hotel_count.txt
echo "Initial hotel count: $INITIAL_HOTEL_COUNT"

# Ensure Firefox is open at OrientDB Studio Browse page
echo "Launching Firefox to OrientDB Studio..."
launch_firefox "http://localhost:2480/studio/index.html#/database/demodb/browse" 10

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== delete_vertices task setup complete ==="