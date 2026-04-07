#!/bin/bash
# Export script for MTM CTA Tracking task

echo "=== Exporting MTM Task Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Export Database State to JSON
# We use a python script inside the container to query the DB and handle JSON parsing/dumping
# This is safer than bash string manipulation for JSON columns

cat > /tmp/export_mtm_data.py << 'PYEOF'
import json
import pymysql
import os
import time

# DB Credentials
db_config = {
    'host': 'db',
    'user': 'matomo',
    'password': 'matomo123',
    'db': 'matomo',
    'charset': 'utf8mb4',
    'cursorclass': pymysql.cursors.DictCursor
}

output = {
    'triggers': [],
    'tags': [],
    'versions': [],
    'task_start': 0
}

try:
    # Get task start time
    if os.path.exists('/tmp/task_start_time.txt'):
        with open('/tmp/task_start_time.txt', 'r') as f:
            output['task_start'] = int(f.read().strip())

    connection = pymysql.connect(**db_config)
    with connection.cursor() as cursor:
        
        # 1. Get Triggers
        # We fetch id, name, and the raw JSON parameters
        cursor.execute("SELECT idtrigger, name, parameters, modified_date FROM matomo_tagmanager_trigger WHERE deleted=0")
        triggers = cursor.fetchall()
        for t in triggers:
            try:
                # parameters column is a JSON string, parse it
                t['parameters'] = json.loads(t['parameters'])
            except:
                pass
            # Convert datetime to string
            t['modified_date'] = str(t['modified_date'])
            output['triggers'].append(t)

        # 2. Get Tags
        cursor.execute("SELECT idtag, name, parameters, modified_date FROM matomo_tagmanager_tag WHERE deleted=0")
        tags = cursor.fetchall()
        for t in tags:
            try:
                t['parameters'] = json.loads(t['parameters'])
            except:
                pass
            t['modified_date'] = str(t['modified_date'])
            output['tags'].append(t)

        # 3. Get Container Versions
        # We need to check if a new version was created/published
        cursor.execute("SELECT idcontainerver, name, ts_created FROM matomo_tagmanager_container_version WHERE deleted=0")
        versions = cursor.fetchall()
        for v in versions:
            # Convert timestamp to unix if needed, or string
            v['ts_created'] = v['ts_created'].timestamp() if hasattr(v['ts_created'], 'timestamp') else str(v['ts_created'])
            output['versions'].append(v)

    connection.close()

except Exception as e:
    output['error'] = str(e)

print(json.dumps(output, indent=2))
PYEOF

# Execute the python script inside the matomo-app container (where python + mysql-connector should be)
# Note: The environment has pymysql installed in the main container, but we need to query the DB.
# We can run this script on the host (ga user) and connect to the db container if port 3306 is exposed,
# OR we can exec into the container.
# The setup_matomo.sh installs python3-pymysql on the host. We should use that.
# The docker-compose usually exposes db on a network. We need to check if 'db' host resolves from here.
# Typically in these environments, we access mysql via `docker exec matomo-db ...`.
# Python approach requires the library.
# Let's fallback to `docker exec` if the python script fails, but `docker exec` with complex JSON is hard.
# BETTER STRATEGY: Use `docker exec` to run the python script INSIDE the `matomo-app` container if it has python.
# `matomo-app` is based on php:apache, might not have python.
# `matomo-db` has mysql client.

# Let's try running python on the HOST (where we are) and assume we can reach the DB.
# If not, we use `docker exec matomo-db mysql ...` and process text.

# Check if we can reach the DB from host
if ping -c 1 db &> /dev/null; then
    # We are likely inside the docker network or linked? Usually not in this env setup.
    # We rely on `docker exec matomo-db`.
    USE_PYTHON_HOST=false
else
    # We probably can't connect directly to 'db' hostname from the agent environment shell
    # unless it's in /etc/hosts.
    USE_PYTHON_HOST=false
fi

# Creating a PHP script to run INSIDE the matomo container is the most robust way
# because Matomo container definitely has PHP and DB access.

cat > /tmp/export_mtm.php << 'PHPEOF'
<?php
// Load Matomo bootstrap to get DB config? Too complex.
// Just connect using standard credentials known from setup script.

$host = 'db';
$db   = 'matomo';
$user = 'matomo';
$pass = 'matomo123';
$charset = 'utf8mb4';

$dsn = "mysql:host=$host;dbname=$db;charset=$charset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
];

try {
    $pdo = new PDO($dsn, $user, $pass, $options);
    
    $output = [
        'triggers' => [],
        'tags' => [],
        'versions' => []
    ];

    // Get Triggers
    $stmt = $pdo->query("SELECT idtrigger, name, parameters, modified_date FROM matomo_tagmanager_trigger WHERE deleted=0");
    while ($row = $stmt->fetch()) {
        $row['parameters'] = json_decode($row['parameters'], true);
        $output['triggers'][] = $row;
    }

    // Get Tags
    $stmt = $pdo->query("SELECT idtag, name, parameters, modified_date FROM matomo_tagmanager_tag WHERE deleted=0");
    while ($row = $stmt->fetch()) {
        $row['parameters'] = json_decode($row['parameters'], true);
        $output['tags'][] = $row;
    }

    // Get Versions
    $stmt = $pdo->query("SELECT idcontainerver, name, ts_created FROM matomo_tagmanager_container_version WHERE deleted=0");
    while ($row = $stmt->fetch()) {
        $output['versions'][] = $row;
    }

    echo json_encode($output);

} catch (\PDOException $e) {
    echo json_encode(['error' => $e->getMessage()]);
}
?>
PHPEOF

# Copy PHP script to container
docker cp /tmp/export_mtm.php matomo-app:/var/www/html/export_mtm.php

# Run it
docker exec matomo-app php /var/www/html/export_mtm.php > /tmp/mtm_export_raw.json

# Add task info (start time) from host
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Merge using jq if available, or python
python3 -c "
import json
try:
    with open('/tmp/mtm_export_raw.json') as f:
        data = json.load(f)
    data['task_start'] = $TASK_START
    print(json.dumps(data, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# Cleanup
rm -f /tmp/export_mtm.php /tmp/mtm_export_raw.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="