#!/bin/bash
echo "=== Setting up create_class task ==="
# Ensure safe PATH (guards against /etc/environment corruption)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is running
wait_for_orientdb 60

# Reset state: drop 'Airports' class if it was created by a previous run
if orientdb_class_exists "demodb" "Airports"; then
    echo "Airports class exists from previous run, dropping it..."
    orientdb_sql "demodb" "DROP CLASS Airports UNSAFE" > /dev/null 2>&1 || true
    sleep 1
fi

# Ensure demodb is healthy
echo "demodb classes:"
curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
classes = [c['name'] for c in data.get('classes', []) if not c['name'].startswith('_')]
print('  ' + ', '.join(sorted(classes)))
" 2>/dev/null || echo "  (could not retrieve class list)"

# Launch Firefox to OrientDB Studio home page (agent will log in and navigate)
echo "Launching Firefox to OrientDB Studio..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

# Take initial screenshot for verification
take_screenshot /tmp/task_start_create_class.png
echo "Initial screenshot saved to /tmp/task_start_create_class.png"

echo "=== create_class task setup complete ==="
echo "Task: Connect to demodb → Schema tab → Create class 'Airports' with properties"
