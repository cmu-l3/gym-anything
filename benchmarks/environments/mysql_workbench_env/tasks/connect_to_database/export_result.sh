#!/bin/bash
# Export script for connect_to_database task

echo "=== Exporting Connect to Database Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Expected values
EXPECTED_NAME="SakilaDB"
EXPECTED_HOST="localhost"
EXPECTED_PORT="3306"
EXPECTED_USER="ga"

# Initialize variables
WORKBENCH_RUNNING=$(is_workbench_running)
CONNECTION_FOUND="false"
CONNECTION_NAME=""
CONNECTION_HOST=""
CONNECTION_PORT=""
CONNECTION_USER=""
NEW_CONNECTION="false"
CONNECTION_WORKING="false"

# Get initial connection count
INITIAL_COUNT=$(cat /tmp/initial_connection_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(count_workbench_connections)

echo "Initial connections: $INITIAL_COUNT"
echo "Current connections: $CURRENT_COUNT"

# Check if new connection was added
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    NEW_CONNECTION="true"
    echo "New connection detected!"
fi

# Check MySQL Workbench connections configuration
# Snap stores data in different locations - search for it
echo "Searching for connections.xml..."

# First, find all connections.xml files
FOUND_FILES=$(find /home/ga -name "connections.xml" 2>/dev/null)
echo "Found files: $FOUND_FILES"

# Also search in snap directories with common patterns
SNAP_CONNECTIONS=""
for dir in /home/ga/snap/mysql-workbench-community/*/; do
    if [ -d "$dir" ]; then
        POSSIBLE_FILE=$(find "$dir" -name "connections.xml" 2>/dev/null | head -1)
        if [ -n "$POSSIBLE_FILE" ]; then
            SNAP_CONNECTIONS="$POSSIBLE_FILE"
            break
        fi
    fi
done

# Standard location
CONNECTIONS_FILE="/home/ga/.mysql/workbench/connections.xml"
SERVER_INSTANCES_FILE=""

# For snap version, also check server_instances.xml which stores connection data
echo "Checking for server_instances.xml in snap directories..."
for dir in /home/ga/snap/mysql-workbench-community/*/; do
    if [ -d "$dir" ]; then
        POSSIBLE_FILE=$(find "$dir" -name "server_instances.xml" 2>/dev/null | head -1)
        if [ -n "$POSSIBLE_FILE" ] && [ -f "$POSSIBLE_FILE" ]; then
            SERVER_INSTANCES_FILE="$POSSIBLE_FILE"
            echo "Found server_instances.xml: $SERVER_INSTANCES_FILE"
            break
        fi
    fi
done

# Find the connections file - prioritize snap location
if [ -n "$SNAP_CONNECTIONS" ] && [ -f "$SNAP_CONNECTIONS" ]; then
    CONNECTIONS_FILE="$SNAP_CONNECTIONS"
    echo "Using snap connections file: $SNAP_CONNECTIONS"
elif [ -f "$CONNECTIONS_FILE" ]; then
    echo "Using standard connections file: $CONNECTIONS_FILE"
elif [ -n "$FOUND_FILES" ]; then
    CONNECTIONS_FILE=$(echo "$FOUND_FILES" | head -1)
    echo "Using found connections file: $CONNECTIONS_FILE"
else
    echo "No connections.xml found - will check server_instances.xml instead..."
fi

# First check server_instances.xml (snap version stores data here)
if [ -f "$SERVER_INSTANCES_FILE" ]; then
    echo "Parsing server_instances.xml..."

    # Check for expected connection name
    if grep -qi "$EXPECTED_NAME" "$SERVER_INSTANCES_FILE" 2>/dev/null; then
        CONNECTION_FOUND="true"
        CONNECTION_NAME="$EXPECTED_NAME"
        echo "Connection '$EXPECTED_NAME' found in server_instances.xml!"

        # Extract connection details from server_instances.xml
        CONN_DETAILS=$(python3 -c "
import xml.etree.ElementTree as ET
import json
try:
    tree = ET.parse('$SERVER_INSTANCES_FILE')
    root = tree.getroot()
    for inst in root.findall('.//value[@struct-name=\"db.mgmt.ServerInstance\"]'):
        name_elem = inst.find('.//value[@key=\"name\"]')
        if name_elem is not None and '$EXPECTED_NAME'.lower() in (name_elem.text or '').lower():
            # Get the connection link ID and look up connection details
            conn_link = inst.find('.//link[@struct-name=\"db.mgmt.Connection\"]')
            if conn_link is not None:
                conn_id = conn_link.text
                # The connection details might be in the same file or linked
                print(json.dumps({'name': name_elem.text or '', 'found': True}))
                break
except Exception as e:
    print(json.dumps({'error': str(e), 'found': False}))
" 2>/dev/null)

        if [ -n "$CONN_DETAILS" ]; then
            echo "Connection details: $CONN_DETAILS"
        fi
    fi

    # Show file content for debugging
    echo ""
    echo "Server instances file content:"
    cat "$SERVER_INSTANCES_FILE" | head -50
fi

# Also parse connections file if it exists
if [ -f "$CONNECTIONS_FILE" ] && [ "$CONNECTION_FOUND" = "false" ]; then
    echo "Parsing connections file..."

    # Check for expected connection name (case-insensitive)
    if grep -qi "$EXPECTED_NAME" "$CONNECTIONS_FILE" 2>/dev/null; then
        CONNECTION_FOUND="true"
        CONNECTION_NAME="$EXPECTED_NAME"
        echo "Connection '$EXPECTED_NAME' found!"
    fi

    # Also check for any connection with similar characteristics
    if [ "$CONNECTION_FOUND" = "false" ]; then
        # Check if any connection to localhost exists
        if grep -qi "localhost\|127.0.0.1" "$CONNECTIONS_FILE" 2>/dev/null; then
            # Extract connection names using Python for reliable XML parsing
            CONNECTION_NAME=$(python3 -c "
import xml.etree.ElementTree as ET
try:
    tree = ET.parse('$CONNECTIONS_FILE')
    root = tree.getroot()
    for conn in root.findall('.//value[@struct-name=\"db.mgmt.Connection\"]'):
        name_elem = conn.find('.//*[@key=\"name\"]')
        host_elem = conn.find('.//*[@key=\"hostName\"]')
        if name_elem is not None:
            name = name_elem.text or ''
            host = host_elem.text if host_elem is not None else ''
            if 'sakila' in name.lower() or host in ['localhost', '127.0.0.1']:
                print(name)
                break
except:
    pass
" 2>/dev/null)

            if [ -n "$CONNECTION_NAME" ]; then
                CONNECTION_FOUND="true"
                echo "Found connection: $CONNECTION_NAME"
            fi
        fi
    fi

    # Extract connection details using Python
    if [ "$CONNECTION_FOUND" = "true" ]; then
        CONN_DETAILS=$(python3 -c "
import xml.etree.ElementTree as ET
import json
try:
    tree = ET.parse('$CONNECTIONS_FILE')
    root = tree.getroot()
    for conn in root.findall('.//value[@struct-name=\"db.mgmt.Connection\"]'):
        name_elem = conn.find('.//*[@key=\"name\"]')
        if name_elem is not None:
            name = name_elem.text or ''
            if 'sakila' in name.lower() or '$CONNECTION_NAME'.lower() in name.lower():
                host = ''
                port = ''
                user = ''
                for param in conn.findall('.//*[@struct-name=\"db.mgmt.ConnectionParameter\"]'):
                    key_elem = param.find('.//*[@key=\"key\"]')
                    val_elem = param.find('.//*[@key=\"value\"]')
                    if key_elem is not None and val_elem is not None:
                        k = key_elem.text or ''
                        v = val_elem.text or ''
                        if 'hostname' in k.lower():
                            host = v
                        elif 'port' in k.lower():
                            port = v
                        elif 'username' in k.lower():
                            user = v
                # Also check direct elements
                for elem in conn.findall('.//'):
                    key = elem.get('key', '')
                    if key == 'hostName':
                        host = elem.text or host
                    elif key == 'port':
                        port = elem.text or port
                    elif key == 'userName':
                        user = elem.text or user
                print(json.dumps({'name': name, 'host': host, 'port': port, 'user': user}))
                break
except Exception as e:
    print(json.dumps({'error': str(e)}))
" 2>/dev/null)

        if [ -n "$CONN_DETAILS" ]; then
            CONNECTION_HOST=$(echo "$CONN_DETAILS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('host',''))" 2>/dev/null)
            CONNECTION_PORT=$(echo "$CONN_DETAILS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('port',''))" 2>/dev/null)
            CONNECTION_USER=$(echo "$CONN_DETAILS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('user',''))" 2>/dev/null)
        fi
    fi

    # Show file content for debugging
    echo ""
    echo "Connections file content:"
    cat "$CONNECTIONS_FILE" | head -100
fi

# Test if connection actually works
if [ "$CONNECTION_FOUND" = "true" ]; then
    echo ""
    echo "Testing database connection..."
    if mysql -u ga -ppassword123 -h localhost -e "SELECT 1;" 2>/dev/null; then
        CONNECTION_WORKING="true"
        echo "Database connection verified working"
    fi
fi

# Check for exact name match
EXACT_NAME_MATCH="false"
if echo "$CONNECTION_NAME" | grep -qi "sakiladb"; then
    EXACT_NAME_MATCH="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/connection_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "workbench_running": $WORKBENCH_RUNNING,
    "connection_found": $CONNECTION_FOUND,
    "connection_name": "$CONNECTION_NAME",
    "expected_name": "$EXPECTED_NAME",
    "exact_name_match": $EXACT_NAME_MATCH,
    "connection_host": "$CONNECTION_HOST",
    "connection_port": "$CONNECTION_PORT",
    "connection_user": "$CONNECTION_USER",
    "expected_host": "$EXPECTED_HOST",
    "expected_port": "$EXPECTED_PORT",
    "expected_user": "$EXPECTED_USER",
    "new_connection": $NEW_CONNECTION,
    "initial_connection_count": $INITIAL_COUNT,
    "current_connection_count": $CURRENT_COUNT,
    "connection_working": $CONNECTION_WORKING,
    "connections_file": "$CONNECTIONS_FILE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/connection_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/connection_result.json
chmod 666 /tmp/connection_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/connection_result.json"
cat /tmp/connection_result.json

echo ""
echo "=== Export Complete ==="
