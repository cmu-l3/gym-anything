#!/bin/bash
echo "=== Setting up Configure Session Cleanup task ==="

# Source utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 60

echo "Cleaning up previous state (if any)..."

# 1. Remove OSchedule entry if exists
# We need to find the RID of the schedule first
SCHEDULE_EXISTS=$(orientdb_sql "demodb" "SELECT FROM OSchedule WHERE function.name = 'cleanup_sessions'" | grep -o "#[0-9]*:[0-9]*" | head -1)
if [ -n "$SCHEDULE_EXISTS" ]; then
    echo "Removing existing schedule..."
    orientdb_sql "demodb" "DELETE FROM $SCHEDULE_EXISTS" > /dev/null 2>&1 || true
fi

# 2. Remove Function if exists
# Functions are stored in OFunction class
FUNCTION_EXISTS=$(orientdb_sql "demodb" "SELECT FROM OFunction WHERE name = 'cleanup_sessions'" | grep -o "#[0-9]*:[0-9]*" | head -1)
if [ -n "$FUNCTION_EXISTS" ]; then
    echo "Removing existing function..."
    orientdb_sql "demodb" "DELETE FROM $FUNCTION_EXISTS" > /dev/null 2>&1 || true
fi

# 3. Remove UserSessions class if exists
if orientdb_class_exists "demodb" "UserSessions"; then
    echo "Removing existing UserSessions class..."
    orientdb_sql "demodb" "DROP CLASS UserSessions UNSAFE" > /dev/null 2>&1 || true
fi

# Launch Firefox to OrientDB Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="