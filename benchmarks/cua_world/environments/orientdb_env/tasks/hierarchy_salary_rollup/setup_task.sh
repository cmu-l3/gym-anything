#!/bin/bash
echo "=== Setting up hierarchy_salary_rollup task ==="
set -e

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is running
wait_for_orientdb 60

# Clean state: Drop classes if they exist from previous runs
echo "Cleaning up any previous schema..."
orientdb_sql "demodb" "DROP CLASS ReportsTo UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Staff UNSAFE" > /dev/null 2>&1 || true

# Verify cleanup
echo "Verifying cleanup..."
REMAINING=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM (SELECT expand(classes) FROM metadata:schema) WHERE name IN ['Staff', 'ReportsTo']" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

if [ "$REMAINING" != "0" ]; then
    echo "WARNING: Cleanup might have failed, schema still exists."
fi

# Remove any previous output file
rm -f /home/ga/salary_rollup.json

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="