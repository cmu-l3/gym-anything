#!/bin/bash
set -e
echo "=== Setting up refactor_embedded_address task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 120

# 1. RESET STATE
# We need to ensure Hotels has flat Street/City/Country and Location class does NOT exist.
echo "Resetting schema to initial state..."

# Helper to execute SQL
run_sql() {
    orientdb_sql "demodb" "$1" > /dev/null 2>&1 || true
}

# If Address property exists, try to reverse migration (restore flat fields) just in case
# But simply dropping Address and recreating flat fields is safer if we re-populate.
# However, re-populating everything is complex.
# Best approach: Check if "Location" class exists. If so, drop it and fix Hotels.

if orientdb_class_exists "demodb" "Location"; then
    echo "Found existing Location class. Cleaning up..."
    # Drop the Address property from Hotels
    run_sql "DROP PROPERTY Hotels.Address FORCE"
    # Drop the Location class
    run_sql "DROP CLASS Location UNSAFE"
fi

# Ensure flat properties exist on Hotels
for prop in Street City Country; do
    # Create property if missing (idempotent-ish check)
    run_sql "CREATE PROPERTY Hotels.$prop STRING"
done

# 2. DATA VERIFICATION / REPAIR
# Check if data exists in flat fields. If not (because of previous run cleanup), restore it.
# We check one hotel.
HOTEL_CHECK=$(orientdb_sql "demodb" "SELECT Street FROM Hotels WHERE Name='Hotel Artemide'" 2>/dev/null)
HAS_DATA=$(echo "$HOTEL_CHECK" | python3 -c "import sys, json; print(1 if json.load(sys.stdin).get('result') and json.load(sys.stdin)['result'][0].get('Street') else 0)" 2>/dev/null || echo "0")

if [ "$HAS_DATA" = "0" ]; then
    echo "Flat data missing. Restoring data from seed..."
    # We can use the existing seed script logic, but it might be faster to just update the specific records if they exist but are empty.
    # Actually, if the previous run deleted the properties, the data is gone.
    # Re-running the hotels seed function is best.
    
    # Drop Hotels class to be safe and re-seed hotels
    run_sql "DELETE VERTEX Hotels"
    # We'll use the python seeder but only the hotels part? 
    # The existing seed_demodb.py is modular but runs all if called directly.
    # Let's just re-run the whole seeder if data is bad. It handles 'already exists' gracefully.
    echo "Data corrupted or missing. Re-seeding database..."
    python3 /workspace/scripts/seed_demodb.py > /dev/null 2>&1
else
    echo "Initial data looks correct."
fi

# 3. GUI SETUP
echo "Launching Firefox..."
kill_firefox
# Start Firefox at the Schema page for Hotels (saves a click, helpful context)
# Or just the Schema home.
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html#/database/demodb/schema' &"
sleep 10

# 4. INITIAL EVIDENCE
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="