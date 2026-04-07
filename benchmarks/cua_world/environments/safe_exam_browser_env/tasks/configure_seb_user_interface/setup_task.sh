#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_seb_user_interface task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure SEB Server is running
wait_for_seb_server 120

# ============================================================
# Create the exam configuration via REST API
# ============================================================
echo "=== Creating exam configuration via API ==="

# Get OAuth2 token
TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8080/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password&username=super-admin&password=admin&client_id=guiClient&client_secret=" \
    2>/dev/null || echo "{}")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -z "$ACCESS_TOKEN" ]; then
    echo "WARNING: Could not get OAuth token, trying alternative auth..."
    TOKEN_RESPONSE=$(curl -s -X POST "http://localhost:8080/oauth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "grant_type=password&username=super-admin&password=admin&client_id=guiClient&client_secret=guiClientSecret" \
        2>/dev/null || echo "{}")
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
fi

if [ -n "$ACCESS_TOKEN" ]; then
    echo "Got access token, creating exam configuration..."

    # Create the exam configuration
    CONFIG_RESPONSE=$(curl -s -X POST "http://localhost:8080/admin-api/v1/configuration-node" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Certification Exam Fall 2024",
            "description": "SEB configuration for proctored certification exam at the testing center",
            "type": "EXAM_CONFIG",
            "status": "CONSTRUCTION",
            "institutionId": 1
        }' 2>/dev/null || echo "{}")

    CONFIG_NODE_ID=$(echo "$CONFIG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

    if [ -n "$CONFIG_NODE_ID" ] && [ "$CONFIG_NODE_ID" != "" ]; then
        echo "Created exam configuration with node ID: $CONFIG_NODE_ID"
        echo "$CONFIG_NODE_ID" > /tmp/config_node_id.txt
        sleep 5 # Wait for backend to populate default settings
    else
        echo "WARNING: API config creation failed, response: $CONFIG_RESPONSE"
    fi
fi

# ============================================================
# Fallback: Create via database if API didn't work
# ============================================================
if [ ! -f /tmp/config_node_id.txt ] || [ ! -s /tmp/config_node_id.txt ]; then
    echo "=== Attempting database fallback ==="
    EXISTING_ID=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT id FROM configuration_node WHERE name='Certification Exam Fall 2024' LIMIT 1;" 2>/dev/null | tr -d '[:space:]' || echo "")
    
    if [ -z "$EXISTING_ID" ]; then
        docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "INSERT INTO configuration_node (institution_id, template_id, name, description, type, status, owner) VALUES (1, NULL, 'Certification Exam Fall 2024', 'SEB configuration for proctored certification exam', 'EXAM_CONFIG', 'CONSTRUCTION', 'super-admin');" 2>/dev/null || true
        EXISTING_ID=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT id FROM configuration_node WHERE name='Certification Exam Fall 2024' LIMIT 1;" 2>/dev/null | tr -d '[:space:]' || echo "")
    fi

    if [ -n "$EXISTING_ID" ]; then
        echo "Configuration node ID (from DB): $EXISTING_ID"
        echo "$EXISTING_ID" > /tmp/config_node_id.txt
        CONFIG_EXISTS=$(docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -N -e "SELECT COUNT(*) FROM configuration WHERE configuration_node_id=$EXISTING_ID;" 2>/dev/null | tr -d '[:space:]')
        if [ "$CONFIG_EXISTS" = "0" ]; then
            docker exec seb-server-mariadb mysql -u root -psebserver123 SEBServer -e "INSERT INTO configuration (institution_id, configuration_node_id, version, version_date, followup) VALUES (1, $EXISTING_ID, 'v0', NOW(), 0);" 2>/dev/null || true
        fi
    fi
fi

# ============================================================
# Record baseline values for anti-gaming
# ============================================================
echo "=== Recording baseline configuration values ==="

python3 << 'PYEOF'
import subprocess
import json
import time
import os

def db_query(query):
    try:
        result = subprocess.run(
            ['docker', 'exec', 'seb-server-mariadb', 'mysql', '-u', 'root',
             '-psebserver123', 'SEBServer', '-N', '-e', query],
            capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip()
    except Exception:
        return ""

try:
    node_id = db_query("SELECT id FROM configuration_node WHERE name='Certification Exam Fall 2024' LIMIT 1")
    if node_id:
        config_id = db_query(f"SELECT id FROM configuration WHERE configuration_node_id={node_id} ORDER BY id DESC LIMIT 1")
        if config_id:
            # Query all values and attributes
            raw_data = db_query(f"""
                SELECT ca.name, cv.value 
                FROM configuration_value cv 
                JOIN configuration_attribute ca ON cv.configuration_attribute_id = ca.id 
                WHERE cv.configuration_id={config_id}
            """)
            
            baseline = {}
            for line in raw_data.split('\n'):
                parts = line.split('\t')
                if len(parts) == 2:
                    baseline[parts[0]] = parts[1]
            
            baseline['_config_id'] = config_id
            baseline['_node_id'] = node_id
            baseline['_timestamp'] = time.time()
            
            with open('/tmp/baseline_config_values.json', 'w') as f:
                json.dump(baseline, f, indent=2)
            print("Baseline recorded successfully.")
except Exception as e:
    print(f"WARNING: Baseline recording failed: {e}")
PYEOF

# ============================================================
# Launch Firefox and log in
# ============================================================
echo "=== Launching Firefox ==="
launch_firefox "http://localhost:8080"
sleep 5

echo "=== Logging into SEB Server ==="
login_seb_server "super-admin" "admin"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="