#!/bin/bash
echo "=== Exporting reassign_menu_item_category result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Load ground truth info
SIDES_ID=$(cat /tmp/task_ground_truth/sides_id.txt 2>/dev/null)
ENTREE_ID=$(cat /tmp/task_ground_truth/entree_id.txt 2>/dev/null)
NAAN_ID=$(cat /tmp/task_ground_truth/naan_id.txt 2>/dev/null)
DB_PATH=$(cat /tmp/task_ground_truth/db_path.txt 2>/dev/null)
DERBY_CP=$(cat /tmp/task_ground_truth/derby_cp.txt 2>/dev/null)

# Prepare initial values for JSON
NAAN_EXISTS="false"
CURRENT_CAT_ID="-1"
PRICE_CHANGED="false"
CATEGORY_NAME="unknown"

# Need to stop Floreant to query embedded Derby DB
if pgrep -f "floreantpos.jar" > /dev/null; then
    APP_WAS_RUNNING="true"
    echo "Stopping Floreant POS for database verification..."
    pkill -f "floreantpos.jar" 2>/dev/null || true
    sleep 3
    pkill -9 -f "floreantpos.jar" 2>/dev/null || true
else
    APP_WAS_RUNNING="false"
fi

if [ -n "$DB_PATH" ] && [ -n "$DERBY_CP" ] && [ -n "$NAAN_ID" ]; then
    # Query current state
    echo "Querying database..."
    
    # We query: Category ID, Name, Price
    QUERY_RES=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << EOF 2>&1
connect 'jdbc:derby:${DB_PATH}';
SELECT CATEGORY_ID, NAME, PRICE FROM MENU_ITEM WHERE ID=${NAAN_ID};
disconnect;
exit;
EOF
)
    
    # Parse results (Derby output is messy, contains headers)
    # Look for the line with the data. It's usually pipe-delimited or fixed width in ij
    # Simple grep strategy
    if echo "$QUERY_RES" | grep -q "${NAAN_ID}"; then
        # This implies we found the ID in the SELECT output? No, we didn't select ID.
        # But we selected by ID. If rows returned, Naan exists.
        # Let's rely on finding "Garlic Naan" in output.
        pass
    fi
    
    if echo "$QUERY_RES" | grep -qi "Garlic Naan"; then
        NAAN_EXISTS="true"
        
        # Extract Category ID. 
        # Expected row format in ij output: "123        |Garlic Naan         |4.99 "
        # We need to be careful about parsing.
        
        # Let's clean the output to just the data row
        DATA_ROW=$(echo "$QUERY_RES" | grep -i "Garlic Naan" | head -1)
        
        # Assume first column is CATEGORY_ID
        CURRENT_CAT_ID=$(echo "$DATA_ROW" | awk -F'|' '{print $1}' | tr -d '[:space:]')
        
        # Get Price to check collateral damage
        CURRENT_PRICE=$(echo "$DATA_ROW" | awk -F'|' '{print $3}' | tr -d '[:space:]')
        
        # Compare price with initial (assuming 4.99 from setup)
        # Note: robust implementation would read initial price from /tmp/task_ground_truth/initial_props.txt
        # Setup created it with 4.99.
        if [[ "$CURRENT_PRICE" != "4.99" && "$CURRENT_PRICE" != "4.9900" ]]; then
            PRICE_CHANGED="true"
        fi
        
        # Get Category Name for the current category ID for better feedback
        CAT_NAME_RES=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << CATQ 2>&1
connect 'jdbc:derby:${DB_PATH}';
SELECT NAME FROM MENU_CATEGORY WHERE ID=${CURRENT_CAT_ID};
disconnect;
exit;
CATQ
)
        # Extract name (e.g., "SIDES")
        # Grep for likely names or just clean the output
        CATEGORY_NAME=$(echo "$CAT_NAME_RES" | grep -v "ij>" | grep -v "NAME" | grep -v "\-\-\-" | grep -v "connect" | grep -v "disconnect" | grep -v "exit" | grep -v "^$" | head -1 | xargs)
    fi
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_WAS_RUNNING,
    "naan_exists": $NAAN_EXISTS,
    "current_category_id": "$CURRENT_CAT_ID",
    "current_category_name": "$CATEGORY_NAME",
    "price_changed": $PRICE_CHANGED,
    "expected_sides_id": "$SIDES_ID",
    "expected_entree_id": "$ENTREE_ID",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="