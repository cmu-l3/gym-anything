#!/bin/bash
set -e
echo "=== Setting up reassign_menu_item_category task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any existing Floreant instance to unlock DB
kill_floreant
sleep 2

# Restore clean database state from backup
echo "Restoring clean database state..."
DB_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
BACKUP_DIR="/opt/floreantpos/posdb_backup"

if [ -d "$BACKUP_DIR" ] && [ -n "$DB_DIR" ]; then
    rm -rf "$DB_DIR"
    cp -r "$BACKUP_DIR" "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    echo "Database restored from backup"
elif [ -d "/opt/floreantpos/derby_server_backup" ]; then
    # Fallback structure
    rm -rf /opt/floreantpos/database/derby-server
    cp -r /opt/floreantpos/derby_server_backup /opt/floreantpos/database/derby-server
    chown -R ga:ga /opt/floreantpos/database/derby-server
    echo "Derby server restored from backup"
fi

# Locate Derby resources for setup
DERBY_CP=$(find /opt/floreantpos/lib -name "derby*.jar" 2>/dev/null | tr '\n' ':')
DB_PATH=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_PATH" ]; then
    DB_PATH="/opt/floreantpos/database/derby-server/posdb"
fi

# Create ground truth directory
mkdir -p /tmp/task_ground_truth
chmod 777 /tmp/task_ground_truth

# ------------------------------------------------------------------
# DATABASE PREPARATION
# We must ensure 'SIDES' and 'ENTREE' categories exist
# and 'Garlic Naan' exists and is assigned to 'ENTREE'.
# ------------------------------------------------------------------
echo "Preparing database data..."

cat > /tmp/setup_data.ij << IJEOF
connect 'jdbc:derby:${DB_PATH}';

-- 1. Get IDs for categories if they exist
SELECT ID, NAME FROM MENU_CATEGORY WHERE UPPER(NAME) IN ('SIDES', 'ENTREE');

disconnect;
exit;
IJEOF

# Execute discovery query
QUERY_OUT=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij /tmp/setup_data.ij 2>&1)

# Helper to find next ID
get_next_id() {
    java -cp "${DERBY_CP}" org.apache.derby.tools.ij << MAXEOF 2>&1 | grep -oP '^\s*\d+' | tail -1
connect 'jdbc:derby:${DB_PATH}';
SELECT MAX(ID) FROM $1;
disconnect;
exit;
MAXEOF
}

# Check existence and create setup script
cat > /tmp/create_data.ij << IJEOF
connect 'jdbc:derby:${DB_PATH}';
IJEOF

# SIDES CATEGORY
if echo "$QUERY_OUT" | grep -qi "SIDES"; then
    # Extract existing ID
    SIDES_ID=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << SEQ 2>&1 | grep -oP '^\s*\d+' | tail -1
connect 'jdbc:derby:${DB_PATH}';
SELECT ID FROM MENU_CATEGORY WHERE UPPER(NAME)='SIDES';
disconnect;
exit;
SEQ
)
    echo "SIDES exists with ID $SIDES_ID"
else
    MAX_ID=$(get_next_id "MENU_CATEGORY")
    SIDES_ID=$((MAX_ID + 1))
    echo "INSERT INTO MENU_CATEGORY (ID, NAME, VISIBLE, BEVERAGE, SORT_ORDER) VALUES ($SIDES_ID, 'SIDES', true, false, $SIDES_ID);" >> /tmp/create_data.ij
    echo "Creating SIDES with ID $SIDES_ID"
fi

# ENTREE CATEGORY
if echo "$QUERY_OUT" | grep -qi "ENTREE"; then
    ENTREE_ID=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << SEQ 2>&1 | grep -oP '^\s*\d+' | tail -1
connect 'jdbc:derby:${DB_PATH}';
SELECT ID FROM MENU_CATEGORY WHERE UPPER(NAME)='ENTREE';
disconnect;
exit;
SEQ
)
    echo "ENTREE exists with ID $ENTREE_ID"
else
    # Need new max ID, accounting for potential SIDES creation
    MAX_ID=$(get_next_id "MENU_CATEGORY")
    if [ "$MAX_ID" -lt "$SIDES_ID" ]; then MAX_ID=$SIDES_ID; fi
    ENTREE_ID=$((MAX_ID + 1))
    echo "INSERT INTO MENU_CATEGORY (ID, NAME, VISIBLE, BEVERAGE, SORT_ORDER) VALUES ($ENTREE_ID, 'ENTREE', true, false, $ENTREE_ID);" >> /tmp/create_data.ij
    echo "Creating ENTREE with ID $ENTREE_ID"
fi

# GARLIC NAAN ITEM
NAAN_ID=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << SEQ 2>&1 | grep -oP '^\s*\d+' | tail -1
connect 'jdbc:derby:${DB_PATH}';
SELECT ID FROM MENU_ITEM WHERE UPPER(NAME)='GARLIC NAAN';
disconnect;
exit;
SEQ
)

if [ -n "$NAAN_ID" ]; then
    echo "Garlic Naan exists (ID: $NAAN_ID). Moving to ENTREE ($ENTREE_ID)..."
    echo "UPDATE MENU_ITEM SET CATEGORY_ID=$ENTREE_ID WHERE ID=$NAAN_ID;" >> /tmp/create_data.ij
else
    MAX_ITEM_ID=$(get_next_id "MENU_ITEM")
    NAAN_ID=$((MAX_ITEM_ID + 1))
    
    # Get valid dependencies
    GROUP_ID=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << GRP 2>&1 | grep -oP '^\s*\d+' | head -1
connect 'jdbc:derby:${DB_PATH}';
SELECT MIN(ID) FROM MENU_GROUP;
disconnect;
exit;
GRP
)
    TAX_ID=$(java -cp "${DERBY_CP}" org.apache.derby.tools.ij << TAX 2>&1 | grep -oP '^\s*\d+' | head -1
connect 'jdbc:derby:${DB_PATH}';
SELECT MIN(ID) FROM TAX;
disconnect;
exit;
TAX
)
    # Defaults
    GROUP_ID=${GROUP_ID:-1}
    TAX_ID=${TAX_ID:-1}
    
    echo "Creating Garlic Naan (ID: $NAAN_ID) in ENTREE..."
    echo "INSERT INTO MENU_ITEM (ID, NAME, PRICE, CATEGORY_ID, GROUP_ID, TAX_ID, VISIBLE, SHOW_IMAGE_ONLY, DISCOUNT_RATE, SORT_ORDER) VALUES ($NAAN_ID, 'Garlic Naan', 4.99, $ENTREE_ID, $GROUP_ID, $TAX_ID, true, false, 0.0, $NAAN_ID);" >> /tmp/create_data.ij
fi

echo "disconnect;" >> /tmp/create_data.ij
echo "exit;" >> /tmp/create_data.ij

# Apply SQL updates
java -cp "${DERBY_CP}" org.apache.derby.tools.ij /tmp/create_data.ij > /dev/null

# Save Ground Truth for export script to use
echo "$SIDES_ID" > /tmp/task_ground_truth/sides_id.txt
echo "$ENTREE_ID" > /tmp/task_ground_truth/entree_id.txt
echo "$NAAN_ID" > /tmp/task_ground_truth/naan_id.txt
echo "$DB_PATH" > /tmp/task_ground_truth/db_path.txt
echo "$DERBY_CP" > /tmp/task_ground_truth/derby_cp.txt

# Store initial properties for collateral damage check
java -cp "${DERBY_CP}" org.apache.derby.tools.ij << PROP > /tmp/task_ground_truth/initial_props.txt 2>&1
connect 'jdbc:derby:${DB_PATH}';
SELECT ID, NAME, PRICE, VISIBLE FROM MENU_ITEM WHERE ID=$NAAN_ID;
disconnect;
exit;
PROP

# Start Floreant POS
start_and_login

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="