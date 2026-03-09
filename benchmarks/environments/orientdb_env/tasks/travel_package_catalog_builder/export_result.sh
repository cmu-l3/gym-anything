#!/bin/bash
echo "=== Exporting Travel Package Catalog Builder results ==="
set -e

# Source utilities
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Helper function to run SQL and get JSON result
run_query() {
    local sql="$1"
    # Use curl directly to avoid quoting hell with the helper function for complex queries
    curl -s -X POST \
        -u "${ORIENTDB_AUTH}" \
        -H "Content-Type: application/json" \
        -d "{\"command\":\"${sql}\"}" \
        "${ORIENTDB_URL}/command/demodb/sql"
}

echo "Collecting Schema Information..."
# Get database schema to check classes and properties
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

echo "Collecting Data..."

# Check Prices on specific entities
PRICES_JSON=$(run_query "SELECT Name, @class as Class, Price FROM V WHERE Name IN ['Hotel Artemide', 'Hotel de Crillon', 'Park Hyatt Tokyo', 'Roma Sparita', 'Le Jules Verne', 'Sushi Saito', 'Colosseum', 'Eiffel Tower', 'Tokyo Tower']")

# Check Packages and their TotalPrice
PACKAGES_JSON=$(run_query "SELECT Name, TotalPrice FROM Packages")

# Check Graph Structure: Package -> Included Items
# We want to know which items are linked to which package
GRAPH_JSON=$(run_query "SELECT Name as PackageName, out('IncludesItem').Name as Items, out('IncludesItem').Price as ItemPrices FROM Packages")

# Timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# Combine into a single JSON file using Python
python3 -c "
import json
import sys

try:
    schema = json.loads('''$SCHEMA_JSON''')
    prices = json.loads('''$PRICES_JSON''')
    packages = json.loads('''$PACKAGES_JSON''')
    graph = json.loads('''$GRAPH_JSON''')
except Exception as e:
    print(f'Error parsing JSON inputs: {e}', file=sys.stderr)
    schema, prices, packages, graph = {}, {}, {}, {}

result = {
    'timestamp': $NOW,
    'task_start': $TASK_START,
    'schema': schema,
    'entity_prices': prices.get('result', []),
    'packages': packages.get('result', []),
    'graph_structure': graph.get('result', [])
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so verifier can read it (via copy_from_env)
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="