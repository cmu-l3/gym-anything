#!/bin/bash
# Export script for Matomo Tag Manager task

echo "=== Exporting Tag Manager Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to escape JSON string content for inclusion in our output JSON
escape_json_string() {
    # Escape backslashes, double quotes, newlines, tabs
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g; s/\r/\\r/g'
}

# 1. Get Container Info
# We look for any container associated with idsite=1 created/modified recently
echo "Fetching Container info..."
CONTAINER_JSON=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "
    SELECT JSON_OBJECT(
        'idcontainer', idcontainer,
        'name', name,
        'status', status,
        'created_date', created_date
    )
    FROM matomo_tagmanager_container 
    WHERE idsite=1 AND deleted_date IS NULL 
    LIMIT 1;
" 2>/dev/null)

# 2. Get Tags Info (fetch all active tags for site 1)
# Note: fire_trigger_ids is stored as a JSON array string in the DB
echo "Fetching Tags info..."
# We use a trick to construct a JSON array of objects using GROUP_CONCAT if supported, 
# or just fetch lines and let python parse. Matomo's MySQL might support JSON_ARRAYAGG (MySQL 5.7+).
# Fallback: Select rows and format them manually or let the verifier handle a list.
# We'll export raw rows as a JSON array using jq or manual formatting is risky.
# Let's use python inside the script to dump it safely if possible, or just standard SQL output.

# We will export tables to temporary CSV-like format and let verifier parse, 
# OR construct a JSON object using python here.
# Let's use Python for reliable SQL->JSON export to avoid escaping hell in bash.

cat > /tmp/export_tm_data.py << 'PYEOF'
import os
import json
import pymysql.cursors

# Connect to database
connection = pymysql.connect(
    host='127.0.0.1',
    user='matomo',
    password='matomo123',
    database='matomo',
    cursorclass=pymysql.cursors.DictCursor
)

output = {
    "containers": [],
    "tags": [],
    "triggers": [],
    "versions": []
}

try:
    with connection.cursor() as cursor:
        # Fetch Containers
        cursor.execute("SELECT idcontainer, name, status, created_date FROM matomo_tagmanager_container WHERE idsite=1 AND deleted_date IS NULL")
        output["containers"] = cursor.fetchall()
        
        # Fetch Tags
        # parameters and fire_trigger_ids are JSON strings in DB, we keep them as strings to parse later
        cursor.execute("SELECT idtag, name, type, status, parameters, fire_trigger_ids, created_date FROM matomo_tagmanager_tag WHERE idsite=1 AND deleted_date IS NULL")
        output["tags"] = cursor.fetchall()

        # Fetch Triggers
        cursor.execute("SELECT idtrigger, name, type, status, parameters, created_date FROM matomo_tagmanager_trigger WHERE idsite=1 AND deleted_date IS NULL")
        output["triggers"] = cursor.fetchall()

        # Fetch Versions
        cursor.execute("SELECT idcontainerversion, name, status, release_date FROM matomo_tagmanager_container_version WHERE idsite=1 AND deleted_date IS NULL")
        output["versions"] = cursor.fetchall()

finally:
    connection.close()

# Serialize datetime objects to string
def json_serial(obj):
    if hasattr(obj, 'isoformat'):
        return obj.isoformat()
    raise TypeError ("Type not serializable")

print(json.dumps(output, default=json_serial))
PYEOF

# Execute the python script inside the container? 
# No, the python script needs access to the DB. 
# The DB is in a docker container 'matomo-db'.
# We can run the python script on the host (if python/pymysql installed) connected to exposed port, 
# OR run query via docker exec and formatting.
# The environment `install_matomo.sh` installs `python3-pymysql`. 
# BUT the DB port 3306 is not verified exposed to localhost (only linked in docker-compose).
# Better to use `docker exec` with python if available inside, OR `docker exec mysql` to CSV.

# Let's use `docker exec matomo-db mysql` with JSON output helper if available, or simple CSV.
# MySQL 5.7+ supports `SELECT JSON_OBJECT(...)`. Let's assume modern MySQL.

# Attempt to get full JSON dump via SQL
SQL_QUERY="
SELECT JSON_OBJECT(
    'containers', (
        SELECT JSON_ARRAYAGG(JSON_OBJECT('idcontainer', idcontainer, 'name', name, 'created_date', created_date)) 
        FROM matomo_tagmanager_container WHERE idsite=1 AND deleted_date IS NULL
    ),
    'tags', (
        SELECT JSON_ARRAYAGG(JSON_OBJECT('idtag', idtag, 'name', name, 'type', type, 'parameters', parameters, 'fire_trigger_ids', fire_trigger_ids)) 
        FROM matomo_tagmanager_tag WHERE idsite=1 AND deleted_date IS NULL
    ),
    'triggers', (
        SELECT JSON_ARRAYAGG(JSON_OBJECT('idtrigger', idtrigger, 'name', name, 'type', type)) 
        FROM matomo_tagmanager_trigger WHERE idsite=1 AND deleted_date IS NULL
    ),
    'versions', (
        SELECT JSON_ARRAYAGG(JSON_OBJECT('idcontainerversion', idcontainerversion, 'name', name, 'status', status)) 
        FROM matomo_tagmanager_container_version WHERE idsite=1 AND deleted_date IS NULL
    )
);"

# We run this query. If JSON_ARRAYAGG is not supported (older MariaDB/MySQL), it will fail.
# Matomo usually uses MariaDB. MariaDB 10.2+ supports these.
RAW_JSON=$(docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "$SQL_QUERY" 2>/dev/null)

# Fallback mechanism if JSON query failed or returned NULL (e.g. empty tables result in NULL from ARRAYAGG)
if [ -z "$RAW_JSON" ] || [ "$RAW_JSON" == "NULL" ]; then
    echo "Using fallback CSV export..."
    # Export CSVs
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e "SELECT idcontainer, name, created_date FROM matomo_tagmanager_container WHERE idsite=1 AND deleted_date IS NULL" > /tmp/containers.tsv
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e "SELECT idtag, name, type, parameters, fire_trigger_ids FROM matomo_tagmanager_tag WHERE idsite=1 AND deleted_date IS NULL" > /tmp/tags.tsv
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e "SELECT idtrigger, name, type FROM matomo_tagmanager_trigger WHERE idsite=1 AND deleted_date IS NULL" > /tmp/triggers.tsv
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -B -e "SELECT idcontainerversion, name, status FROM matomo_tagmanager_container_version WHERE idsite=1 AND deleted_date IS NULL" > /tmp/versions.tsv
    
    # Convert TSV to JSON using Python on the host
    python3 -c "
import json, csv, sys

data = {'containers': [], 'tags': [], 'triggers': [], 'versions': []}

def read_tsv(fname):
    rows = []
    try:
        with open(fname, 'r') as f:
            reader = csv.DictReader(f, delimiter='\t')
            rows = list(reader)
    except: pass
    return rows

data['containers'] = read_tsv('/tmp/containers.tsv')
data['tags'] = read_tsv('/tmp/tags.tsv')
data['triggers'] = read_tsv('/tmp/triggers.tsv')
data['versions'] = read_tsv('/tmp/versions.tsv')

print(json.dumps(data))
" > /tmp/db_dump.json
    RAW_JSON=$(cat /tmp/db_dump.json)
fi

# Construct final JSON result
TEMP_JSON=$(mktemp /tmp/tm_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_data": $RAW_JSON,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move and set permissions
rm -f /tmp/tag_manager_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/tag_manager_result.json
chmod 666 /tmp/tag_manager_result.json
rm "$TEMP_JSON"

echo "Result saved to /tmp/tag_manager_result.json"
cat /tmp/tag_manager_result.json
echo "=== Export Complete ==="