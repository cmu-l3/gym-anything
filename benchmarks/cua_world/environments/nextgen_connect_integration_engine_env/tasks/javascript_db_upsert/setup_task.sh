#!/bin/bash
echo "=== Setting up javascript_db_upsert task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the target table in PostgreSQL
echo "Creating current_census table..."
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "
DROP TABLE IF EXISTS current_census;
CREATE TABLE current_census (
    mrn VARCHAR(50) PRIMARY KEY,
    patient_name VARCHAR(100),
    location VARCHAR(50),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
echo "$INITIAL_COUNT" > /tmp/initial_channel_count

# Open a terminal for the user
DISPLAY=:1 gnome-terminal --geometry=120x35+70+30 -- bash -c '
echo "============================================"
echo " NextGen Connect - JavaScript DB Upsert"
echo "============================================"
echo ""
echo "TASK: Create channel \"Census_Upsert_Processor\""
echo "GOAL: Sync JSON patient data to DB using JavaScript Writer"
echo ""
echo "Database Connection:"
echo "  URL: jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres"
echo "  Pass: postgres"
echo "  Table: current_census (mrn, patient_name, location, last_updated)"
echo ""
echo "Logic Required in JavaScript Writer:"
echo "  1. Connect to DB"
echo "  2. Check if JSON.mrn exists in table"
echo "  3. If exists -> UPDATE location, patient_name, last_updated"
echo "  4. If not -> INSERT new record"
echo "  5. Close connection"
echo ""
echo "Tools:"
echo "  Check DB: docker exec nextgen-postgres psql -U postgres -d mirthdb -c \"SELECT * FROM current_census;\""
echo "  API: https://localhost:8443/api"
echo "============================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="