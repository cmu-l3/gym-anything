#!/bin/bash
echo "=== Setting up spatial_geofencing_analysis task ==="

# Source utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# 1. Clean up any previous state (Idempotency)
echo "Cleaning previous index and properties..."
# Drop index if exists
orientdb_sql "demodb" "DROP INDEX Hotels.Location" > /dev/null 2>&1 || true

# Drop MarketingZone property if exists (to force creation/flexible schema usage)
# In OrientDB, we can just clear the data to be safe without dropping the property if strictly schema-full, 
# but dropping property is cleaner for 'Create property' instruction.
orientdb_sql "demodb" "UPDATE Hotels REMOVE MarketingZone" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP PROPERTY Hotels.MarketingZone" > /dev/null 2>&1 || true

# 2. Record Initial State
INITIAL_INDEX_EXISTS=$(orientdb_index_exists "demodb" "Hotels.Location" && echo "true" || echo "false")
echo "Initial Index Exists: $INITIAL_INDEX_EXISTS" > /tmp/initial_state.txt

# 3. Launch Firefox to Studio
echo "Launching Firefox..."
kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 10

# 4. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="