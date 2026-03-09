#!/bin/bash
echo "=== Setting up Nationality Normalization Task ==="

# Source utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

# --- Database State Preparation ---

# 1. Reset: Drop IsCitizenOf class if it exists from previous runs
if orientdb_class_exists "demodb" "IsCitizenOf"; then
    echo "Dropping stale IsCitizenOf class..."
    orientdb_sql "demodb" "DROP CLASS IsCitizenOf UNSAFE" > /dev/null 2>&1 || true
fi

# 2. Ensure specific test data exists
# We need specific profiles to test the mapping logic (Adjective -> Noun)

# Ensure Country: United States
orientdb_sql "demodb" "UPDATE Countries SET Name='United States' UPSERT WHERE Name='United States'" > /dev/null

# Ensure Country: United Kingdom
orientdb_sql "demodb" "UPDATE Countries SET Name='United Kingdom' UPSERT WHERE Name='United Kingdom'" > /dev/null

# Ensure Country: Netherlands
orientdb_sql "demodb" "UPDATE Countries SET Name='Netherlands' UPSERT WHERE Name='Netherlands'" > /dev/null

# Ensure 'Mexico' does NOT exist (to test orphan handling)
orientdb_sql "demodb" "DELETE VERTEX Countries WHERE Name='Mexico'" > /dev/null

# Ensure Profile: American (John Smith)
orientdb_sql "demodb" "UPDATE Profiles SET Nationality='American' WHERE Email='john.smith@example.com'" > /dev/null

# Ensure Profile: British (David Jones)
orientdb_sql "demodb" "UPDATE Profiles SET Nationality='British' WHERE Email='david.jones@example.com'" > /dev/null

# Ensure Profile: Dutch (Piet Vanderberg)
# Check if exists first, insert if not
CNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Profiles WHERE Email='piet.vanderberg@example.com'" | grep -o "result\":\[{\"count\":[0-9]*" | cut -d: -f3)
if [ "$CNT" == "0" ]; then
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='piet.vanderberg@example.com', Name='Piet', Surname='Vanderberg', Nationality='Dutch'" > /dev/null
else
    orientdb_sql "demodb" "UPDATE Profiles SET Nationality='Dutch' WHERE Email='piet.vanderberg@example.com'" > /dev/null
fi

# Ensure Profile: Mexican (Carlos Lopez) - The Orphan
CNT=$(orientdb_sql "demodb" "SELECT count(*) FROM Profiles WHERE Email='carlos.lopez@example.com'" | grep -o "result\":\[{\"count\":[0-9]*" | cut -d: -f3)
if [ "$CNT" == "0" ]; then
    orientdb_sql "demodb" "INSERT INTO Profiles SET Email='carlos.lopez@example.com', Name='Carlos', Surname='Lopez', Nationality='Mexican'" > /dev/null
else
    orientdb_sql "demodb" "UPDATE Profiles SET Nationality='Mexican' WHERE Email='carlos.lopez@example.com'" > /dev/null
fi

# 3. Clean up any previous report file
rm -f /home/ga/nationality_audit.txt

# --- Application Setup ---

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="