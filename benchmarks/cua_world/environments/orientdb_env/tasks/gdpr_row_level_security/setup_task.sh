#!/bin/bash
echo "=== Setting up GDPR Row-Level Security Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be fully ready
wait_for_orientdb 120

# Database credentials
DB="demodb"
USER="root"
PASS="GymAnything123!"

# 1. Ensure demodb exists and is populated
if ! orientdb_db_exists "$DB"; then
    echo "Creating demodb..."
    /workspace/scripts/setup_orientdb.sh
fi

# 2. Reset State: Remove artifacts if they exist from previous runs
echo "Cleaning up previous state..."

# Drop User
curl -s -X POST -u "$USER:$PASS" \
    -H "Content-Type: application/json" \
    -d '{"command": "DROP USER us_partner"}' \
    "http://localhost:2480/command/$DB/sql" > /dev/null 2>&1 || true

# Drop Role
curl -s -X POST -u "$USER:$PASS" \
    -H "Content-Type: application/json" \
    -d '{"command": "DROP ROLE us_analytics"}' \
    "http://localhost:2480/command/$DB/sql" > /dev/null 2>&1 || true

# Drop Policy (Requires specific SQL command for security policies if supported via SQL, 
# otherwise we rely on the agent creating it fresh. In ODB 3.x, policies are records in OSecurityPolicy)
curl -s -X POST -u "$USER:$PASS" \
    -H "Content-Type: application/json" \
    -d '{"command": "DELETE FROM OSecurityPolicy WHERE name = \u0027us_only_policy\u0027"}' \
    "http://localhost:2480/command/$DB/sql" > /dev/null 2>&1 || true

# 3. Ensure Data Mix (Americans vs Non-Americans)
echo "Verifying data mix..."
# We need to ensure we have Americans and Non-Americans for the test to be valid
# The seeder usually puts in John Smith (American) and others.
# Let's double check counts.
COUNTS=$(curl -s -X POST -u "$USER:$PASS" \
    -H "Content-Type: application/json" \
    -d '{"command": "SELECT count(*) as total, sum(CASE WHEN Nationality=\u0027American\u0027 THEN 1 ELSE 0 END) as us_count FROM Profiles"}' \
    "http://localhost:2480/command/$DB/sql")

TOTAL=$(echo "$COUNTS" | python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0].get('total', 0))")
US_COUNT=$(echo "$COUNTS" | python3 -c "import sys, json; print(json.load(sys.stdin)['result'][0].get('us_count', 0))")

echo "Data Status: Total Profiles=$TOTAL, American Profiles=$US_COUNT"

if [ "$US_COUNT" -lt 1 ]; then
    echo "Injecting dummy American profile..."
    curl -s -X POST -u "$USER:$PASS" \
        -H "Content-Type: application/json" \
        -d '{"command": "INSERT INTO Profiles SET Name=\u0027Task\u0027, Surname=\u0027Setup\u0027, Nationality=\u0027American\u0027, Email=\u0027task_setup@example.com\u0027"}' \
        "http://localhost:2480/command/$DB/sql" > /dev/null
fi

# 4. Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="