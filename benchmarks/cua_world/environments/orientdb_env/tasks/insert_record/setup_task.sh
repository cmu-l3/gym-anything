#!/bin/bash
echo "=== Setting up insert_record task ==="
# Ensure safe PATH (guards against /etc/environment corruption)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is running
wait_for_orientdb 60

# Reset state: remove 'Portugal' country if it exists from a previous run
echo "Removing Portugal country if it exists..."
orientdb_sql "demodb" "DELETE VERTEX Countries WHERE Name='Portugal'" > /dev/null 2>&1 || true
sleep 1

# Verify demodb Countries data is intact
echo "Current countries in demodb:"
orientdb_sql "demodb" "SELECT Name FROM Countries ORDER BY Name" 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [r.get('Name', '?') for r in data.get('result', [])]
print('  ' + ', '.join(names))
" 2>/dev/null || echo "  (could not retrieve)"

# Launch Firefox to OrientDB Studio (agent will connect and navigate to Browse > Countries)
echo "Launching Firefox to OrientDB Studio..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

take_screenshot /tmp/task_start_insert_record.png
echo "Initial screenshot saved to /tmp/task_start_insert_record.png"

echo "=== insert_record task setup complete ==="
echo "Task: Connect to demodb → Browse tab → Insert Portugal into Countries"
