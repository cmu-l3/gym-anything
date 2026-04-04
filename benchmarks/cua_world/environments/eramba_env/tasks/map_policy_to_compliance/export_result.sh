#!/bin/bash
echo "=== Exporting map_policy_to_compliance result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Retrieve task start time
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Initialize result variables
POLICY_FOUND="false"
POLICY_ID=""
POLICY_CREATED=""
PACKAGE_FOUND="false"
PACKAGE_ID=""
ITEM_FOUND="false"
ITEM_ID=""
LINK_FOUND="false"

# Helper function to run SQL safely
run_sql() {
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "$1" 2>/dev/null
}

echo "Querying database for artifacts..."

# 1. Check Security Policy
# We look for the specific title created after the task start time
POLICY_QUERY="SELECT id, title, description, created FROM security_policies 
              WHERE title LIKE '%Clean Desk%' AND deleted=0 
              AND created >= FROM_UNIXTIME($TASK_START_TIME) 
              ORDER BY id DESC LIMIT 1;"
POLICY_RES=$(run_sql "$POLICY_QUERY")

if [ -n "$POLICY_RES" ]; then
    POLICY_FOUND="true"
    POLICY_ID=$(echo "$POLICY_RES" | cut -f1)
    POLICY_TITLE=$(echo "$POLICY_RES" | cut -f2)
    POLICY_DESC=$(echo "$POLICY_RES" | cut -f3)
    echo "Found Policy: $POLICY_TITLE (ID: $POLICY_ID)"
fi

# 2. Check Compliance Package
PACKAGE_QUERY="SELECT id, name FROM compliance_packages 
               WHERE name LIKE '%ISO 27001%' AND deleted=0 
               AND created >= FROM_UNIXTIME($TASK_START_TIME) 
               ORDER BY id DESC LIMIT 1;"
PACKAGE_RES=$(run_sql "$PACKAGE_QUERY")

if [ -n "$PACKAGE_RES" ]; then
    PACKAGE_FOUND="true"
    PACKAGE_ID=$(echo "$PACKAGE_RES" | cut -f1)
    echo "Found Package ID: $PACKAGE_ID"
fi

# 3. Check Compliance Package Item (Requirement)
# Needs to belong to the package found above if possible, or just match the Item ID
if [ "$PACKAGE_FOUND" = "true" ]; then
    ITEM_QUERY="SELECT id, item_id, name FROM compliance_package_items 
                WHERE compliance_package_id = $PACKAGE_ID 
                AND item_id LIKE '%A.11.2.9%' 
                AND deleted=0 ORDER BY id DESC LIMIT 1;"
    ITEM_RES=$(run_sql "$ITEM_QUERY")
    
    if [ -n "$ITEM_RES" ]; then
        ITEM_FOUND="true"
        ITEM_ID=$(echo "$ITEM_RES" | cut -f1)
        echo "Found Item ID: $ITEM_ID"
    fi
fi

# 4. Check Linkage (Policy <-> Compliance Item)
# Eramba typically uses a join table `compliance_package_items_security_policies`
if [ "$POLICY_FOUND" = "true" ] && [ "$ITEM_FOUND" = "true" ]; then
    LINK_QUERY="SELECT count(*) FROM compliance_package_items_security_policies 
                WHERE compliance_package_item_id = $ITEM_ID 
                AND security_policy_id = $POLICY_ID;"
    LINK_COUNT=$(run_sql "$LINK_QUERY")
    
    if [ "$LINK_COUNT" -gt "0" ]; then
        LINK_FOUND="true"
        echo "Found Linkage between Item $ITEM_ID and Policy $POLICY_ID"
    fi
fi

# 5. Export results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "policy": {
        "found": $POLICY_FOUND,
        "id": "$POLICY_ID",
        "description_snippet": "$(echo "$POLICY_DESC" | head -c 100 | sed 's/"/\\"/g')"
    },
    "package": {
        "found": $PACKAGE_FOUND,
        "id": "$PACKAGE_ID"
    },
    "item": {
        "found": $ITEM_FOUND,
        "id": "$ITEM_ID"
    },
    "linkage": {
        "found": $LINK_FOUND
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="