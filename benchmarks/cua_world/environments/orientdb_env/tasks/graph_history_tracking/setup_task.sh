#!/bin/bash
echo "=== Setting up graph_history_tracking task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 60

echo "Resetting database state..."

# 1. Clean up any previous attempts (drop history classes)
# Use UNSAFE to drop even if data exists
orientdb_sql "demodb" "DROP CLASS HasHistory UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HotelHistory UNSAFE" > /dev/null 2>&1 || true

# 2. Reset specific hotel records to known initial state
# Hotel Artemide: Stars=4
orientdb_sql "demodb" "UPDATE Hotels SET Stars=4 WHERE Name='Hotel Artemide'" > /dev/null

# The Savoy: Phone original
orientdb_sql "demodb" "UPDATE Hotels SET Phone='+44-20-7836-4343' WHERE Name='The Savoy'" > /dev/null

# Hotel Adlon Kempinski: Name original (handle case where it was renamed)
orientdb_sql "demodb" "UPDATE Hotels SET Name='Hotel Adlon Kempinski' WHERE Name='Adlon Kempinski Berlin'" > /dev/null
# Ensure other props are correct just in case
orientdb_sql "demodb" "UPDATE Hotels SET Stars=5 WHERE Name='Hotel Adlon Kempinski'" > /dev/null

# 3. Verify initial state of targets
echo "Verifying initial data..."
orientdb_sql "demodb" "SELECT Name, Stars, Phone FROM Hotels WHERE Name IN ['Hotel Artemide', 'The Savoy', 'Hotel Adlon Kempinski']" | grep "result"

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="