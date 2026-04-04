#!/bin/bash
set -e
echo "=== Setting up link_modifier_to_item task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Kill any running Floreant to access DB
kill_floreant
sleep 2

# Find the Derby database path
DB_DIR=$(find /opt/floreantpos/database -maxdepth 3 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_DIR" ]; then
    echo "ERROR: Could not find Derby database"
    exit 1
fi
echo "Derby DB at: $DB_DIR"

# Find Derby JARs
DERBY_CP=$(find /opt/floreantpos/lib -name "derby*.jar" 2>/dev/null | tr '\n' ':')
if [ -z "$DERBY_CP" ]; then
    # Fallback search
    DERBY_CP=$(find /opt/floreantpos -name "derby.jar" 2>/dev/null | head -1)
    DERBY_TOOLS=$(find /opt/floreantpos -name "derbytools.jar" 2>/dev/null | head -1)
    DERBY_CP="${DERBY_CP}:${DERBY_TOOLS}"
fi

# Create setup SQL script
# Uses high IDs (9901+) to avoid conflicts with existing sample data
cat > /tmp/setup_data.sql << 'SQLEOF'
CONNECT 'jdbc:derby:DB_PATH_PLACEHOLDER';

-- 1. Ensure Category exists
-- Deleting first to ensure clean state for this ID
DELETE FROM MENU_ITEM WHERE ID = 9901;
DELETE FROM MENU_MODIFIER WHERE MODIFIER_GROUP_ID = 9901;
DELETE FROM MENU_MODIFIER_GROUP WHERE ID = 9901;
DELETE FROM MENU_CATEGORY WHERE ID = 9901;

INSERT INTO MENU_CATEGORY (ID, NAME, VISIBLE, BEVERAGE, SORT_ORDER)
    VALUES (9901, 'Entree', true, false, 99);

-- 2. Create Modifier Group "Cooking Preference"
INSERT INTO MENU_MODIFIER_GROUP (ID, NAME, ENABLED)
    VALUES (9901, 'Cooking Preference', true);

-- 3. Create Modifiers
INSERT INTO MENU_MODIFIER (ID, NAME, PRICE, EXTRA_PRICE, MODIFIER_GROUP_ID, SORT_ORDER, ENABLED, TAX_RATE)
    VALUES (9901, 'Rare', 0.00, 0.00, 9901, 0, true, 0.0);
INSERT INTO MENU_MODIFIER (ID, NAME, PRICE, EXTRA_PRICE, MODIFIER_GROUP_ID, SORT_ORDER, ENABLED, TAX_RATE)
    VALUES (9902, 'Medium Rare', 0.00, 0.00, 9901, 1, true, 0.0);
INSERT INTO MENU_MODIFIER (ID, NAME, PRICE, EXTRA_PRICE, MODIFIER_GROUP_ID, SORT_ORDER, ENABLED, TAX_RATE)
    VALUES (9903, 'Medium', 0.00, 0.00, 9901, 2, true, 0.0);
INSERT INTO MENU_MODIFIER (ID, NAME, PRICE, EXTRA_PRICE, MODIFIER_GROUP_ID, SORT_ORDER, ENABLED, TAX_RATE)
    VALUES (9904, 'Well Done', 0.00, 0.00, 9901, 3, true, 0.0);

-- 4. Create Menu Item "Grilled Ribeye Steak"
INSERT INTO MENU_ITEM (ID, NAME, PRICE, VISIBLE, SHOW_IMAGE_ONLY, CATEGORY_ID, DISCOUNT_RATE, SORT_ORDER)
    VALUES (9901, 'Grilled Ribeye Steak', 24.99, true, false, 9901, 0.0, 99);

-- 5. Ensure NO link exists initially
DELETE FROM MENU_ITEM_MODIFIER_GROUP WHERE ITEMS_ID = 9901 OR MENU_ITEM_ID = 9901;

disconnect;
exit;
SQLEOF

# Replace placeholder with actual DB path
sed -i "s|DB_PATH_PLACEHOLDER|${DB_DIR}|g" /tmp/setup_data.sql

# Execute SQL
echo "Inserting test data..."
java -cp "$DERBY_CP" org.apache.derby.tools.ij /tmp/setup_data.sql > /tmp/derby_setup.log 2>&1

if grep -q "ERROR" /tmp/derby_setup.log; then
    echo "WARNING: SQL errors occurred (might be okay if tables existed)"
    cat /tmp/derby_setup.log
fi

# Launch Floreant POS
start_and_login

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="