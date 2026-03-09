#!/bin/bash
echo "=== Setting up create_index task ==="
# Ensure safe PATH (guards against /etc/environment corruption)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is running
wait_for_orientdb 60

# Reset state: drop Hotels.Name index if it exists from a previous run
echo "Dropping Hotels.Name index if it exists..."
orientdb_sql "demodb" "DROP INDEX Hotels.Name" > /dev/null 2>&1 || true
sleep 1

# Verify Hotels data is intact
echo "Current Hotels count:"
orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Hotels" 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
cnt = data.get('result', [{}])[0].get('cnt', '?')
print(f'  Hotels: {cnt} records')
" 2>/dev/null || echo "  (could not retrieve)"

echo "Current indexes on Hotels class:"
curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
for cls in data.get('classes', []):
    if cls['name'] == 'Hotels':
        indexes = cls.get('indexes', [])
        if indexes:
            for idx in indexes:
                print(f'  - {idx[\"name\"]} ({idx.get(\"type\", \"?\")})')
        else:
            print('  (no indexes)')
" 2>/dev/null || echo "  (could not retrieve)"

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

take_screenshot /tmp/task_start_create_index.png
echo "Initial screenshot saved to /tmp/task_start_create_index.png"

echo "=== create_index task setup complete ==="
echo "Task: Connect to demodb → Schema → Hotels class → Create NOTUNIQUE index on Name"
