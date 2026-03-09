#!/bin/bash
echo "=== Exporting Spatial Migration Result ==="

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# --- Data Extraction ---

# We need two things:
# 1. The Schema (to verify Property type and Index existence)
# 2. The Data (to verify City names and Location coordinates)

echo "Extracting Database Schema..."
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

echo "Extracting Hotels Data..."
# We select pertinent fields. Note: ST_AsText(Location) is useful to verify points easily if direct JSON is complex
# But retrieving the raw OPoint object as JSON is standard in OrientDB REST
DATA_JSON=$(orientdb_sql "demodb" "SELECT Name, City, Latitude, Longitude, Location FROM Hotels")

# Combine into a single result file using Python to ensure valid JSON structure
python3 -c "
import json
import sys
import os

try:
    schema_raw = '''$SCHEMA_JSON'''
    data_raw = '''$DATA_JSON'''

    try:
        schema = json.loads(schema_raw)
    except:
        schema = {'error': 'Failed to parse schema'}

    try:
        data = json.loads(data_raw)
    except:
        data = {'result': []}

    output = {
        'schema': schema,
        'data': data.get('result', []),
        'timestamp': '$(date +%s)',
        'screenshot_exists': os.path.exists('/tmp/task_final.png')
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(output, f, indent=2)

except Exception as e:
    print(f'Error creating result JSON: {e}')
    # create fallback
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e)}, f)
"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="