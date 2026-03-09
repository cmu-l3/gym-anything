#!/bin/bash
echo "=== Setting up Spatial Migration & Cleanup task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# --- 1. Reset/Prepare Schema ---
echo "Resetting schema state..."
# Drop the index if it exists
orientdb_sql "demodb" "DROP INDEX Hotels.Location IF EXISTS" > /dev/null 2>&1 || true
# Drop the property if it exists
orientdb_sql "demodb" "DROP PROPERTY Hotels.Location IF EXISTS" > /dev/null 2>&1 || true

# --- 2. Inject Data Corruption (Case Inconsistency) ---
echo "Injecting data inconsistencies..."
# Fix them first to a known state (Title Case) to avoid double-corruption
orientdb_sql "demodb" "UPDATE Hotels SET City='Rome' WHERE City.toLowerCase()='rome'" > /dev/null 2>&1
orientdb_sql "demodb" "UPDATE Hotels SET City='Berlin' WHERE City.toLowerCase()='berlin'" > /dev/null 2>&1
orientdb_sql "demodb" "UPDATE Hotels SET City='Paris' WHERE City.toLowerCase()='paris'" > /dev/null 2>&1

# Apply corruptions
orientdb_sql "demodb" "UPDATE Hotels SET City='rome' WHERE City='Rome'"
orientdb_sql "demodb" "UPDATE Hotels SET City='BERLIN' WHERE City='Berlin'"
orientdb_sql "demodb" "UPDATE Hotels SET City='paris' WHERE City='Paris'"

# --- 3. UI Setup ---
# Launch Firefox to OrientDB Studio (Studio Home)
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "State prepared: Hotels.Location dropped, City names corrupted (rome, BERLIN, paris)."