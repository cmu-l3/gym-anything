#!/bin/bash
echo "=== Setting up create_database task ==="
# Ensure safe PATH (guards against /etc/environment corruption)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Ensure OrientDB is running
wait_for_orientdb 60

# Reset state: drop LibraryDB if it exists from a previous run
if orientdb_db_exists "LibraryDB"; then
    echo "LibraryDB exists from previous run, dropping it..."
    curl -s -X DELETE -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/LibraryDB" > /dev/null 2>&1 || true
    sleep 2
fi

# Also check case variations
for dbname in librarydb LIBRARYDB; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ORIENTDB_AUTH}" \
        "${ORIENTDB_URL}/database/${dbname}" 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        echo "Dropping ${dbname}..."
        curl -s -X DELETE -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/${dbname}" > /dev/null 2>&1 || true
        sleep 1
    fi
done

# List current databases for reference
echo "Current databases:"
curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/listDatabases" 2>/dev/null | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
dbs = data.get('databases', [])
print('  ' + ', '.join(sorted(dbs)))
" 2>/dev/null || echo "  (could not retrieve)"

# Launch Firefox to OrientDB Studio HOME PAGE (not connected to any DB)
# The agent will create a new database from the home screen
echo "Launching Firefox to OrientDB Studio home page..."
kill_firefox
su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/orientdb.profile \
    'http://localhost:2480/studio/index.html' &"
sleep 8

take_screenshot /tmp/task_start_create_database.png
echo "Initial screenshot saved to /tmp/task_start_create_database.png"

echo "=== create_database task setup complete ==="
echo "Task: From Studio home page → create new database named 'LibraryDB' with plocal storage"
