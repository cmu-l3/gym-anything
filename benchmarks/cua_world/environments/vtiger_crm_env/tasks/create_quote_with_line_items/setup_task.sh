#!/bin/bash
set -e

echo "=== Setting up create_quote_with_line_items task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time and initial quote count
date +%s > /tmp/task_start_time.txt
INITIAL_QUOTE_COUNT=$(vtiger_count "vtiger_quotes" "1=1" 2>/dev/null || echo "0")
echo "$INITIAL_QUOTE_COUNT" > /tmp/initial_quote_count.txt
echo "Initial quote count: $INITIAL_QUOTE_COUNT"

# 2. Setup Database Prerequisites (GreenTech Solutions & 3 Products)
echo "--- Creating prerequisite data ---"

cat > /tmp/setup_quote_prereqs.sql << 'SQLEOF'
-- Check if GreenTech Solutions already exists
SET @org_exists = (SELECT COUNT(*) FROM vtiger_account WHERE accountname = 'GreenTech Solutions');

-- Update sequence to get a new ID block
SET @max_id = (SELECT id FROM vtiger_crmentity_seq);

-- Create GreenTech Solutions organization
SET @org_id = @max_id + 1;
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, viewedtime, presence, deleted, label)
SELECT @org_id, 1, 1, 1, 'Accounts', NOW(), NOW(), NOW(), 1, 0, 'GreenTech Solutions'
FROM dual WHERE @org_exists = 0;

INSERT INTO vtiger_account (accountid, accountname, email1, phone, industry)
SELECT @org_id, 'GreenTech Solutions', 'procurement@greentech.example.com', '(512) 555-0142', 'Technology'
FROM dual WHERE @org_exists = 0;

INSERT INTO vtiger_accountbillads (accountaddressid, bill_street, bill_city, bill_state, bill_code, bill_country)
SELECT @org_id, '450 Innovation Drive', 'Austin', 'TX', '73301', 'USA'
FROM dual WHERE @org_exists = 0;

INSERT INTO vtiger_accountshipads (accountaddressid, ship_street, ship_city, ship_state, ship_code, ship_country)
SELECT @org_id, '450 Innovation Drive', 'Austin', 'TX', '73301', 'USA'
FROM dual WHERE @org_exists = 0;

INSERT INTO vtiger_accountscf (accountid)
SELECT @org_id FROM dual WHERE @org_exists = 0;

-- Update sequence if org was created
UPDATE vtiger_crmentity_seq SET id = IF(@org_exists = 0, @org_id, @max_id);

-- Product 1: Wireless Bluetooth Headset
SET @max_id = (SELECT id FROM vtiger_crmentity_seq);
SET @p1_exists = (SELECT COUNT(*) FROM vtiger_products WHERE productname = 'Wireless Bluetooth Headset');
SET @p1_id = @max_id + 1;

INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, viewedtime, presence, deleted, label)
SELECT @p1_id, 1, 1, 1, 'Products', NOW(), NOW(), NOW(), 1, 0, 'Wireless Bluetooth Headset'
FROM dual WHERE @p1_exists = 0;

INSERT INTO vtiger_products (productid, productname, productcode, product_no, unit_price, qtyinstock, discontinued)
SELECT @p1_id, 'Wireless Bluetooth Headset', 'WBH-100', 'PRD-SETUP-001', 49.99, 100, 1
FROM dual WHERE @p1_exists = 0;

INSERT INTO vtiger_productcf (productid)
SELECT @p1_id FROM dual WHERE @p1_exists = 0;

UPDATE vtiger_crmentity_seq SET id = IF(@p1_exists = 0, @p1_id, @max_id);

-- Product 2: USB-C Docking Station
SET @max_id = (SELECT id FROM vtiger_crmentity_seq);
SET @p2_exists = (SELECT COUNT(*) FROM vtiger_products WHERE productname = 'USB-C Docking Station');
SET @p2_id = @max_id + 1;

INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, viewedtime, presence, deleted, label)
SELECT @p2_id, 1, 1, 1, 'Products', NOW(), NOW(), NOW(), 1, 0, 'USB-C Docking Station'
FROM dual WHERE @p2_exists = 0;

INSERT INTO vtiger_products (productid, productname, productcode, product_no, unit_price, qtyinstock, discontinued)
SELECT @p2_id, 'USB-C Docking Station', 'UCD-200', 'PRD-SETUP-002', 129.99, 50, 1
FROM dual WHERE @p2_exists = 0;

INSERT INTO vtiger_productcf (productid)
SELECT @p2_id FROM dual WHERE @p2_exists = 0;

UPDATE vtiger_crmentity_seq SET id = IF(@p2_exists = 0, @p2_id, @max_id);

-- Product 3: Ergonomic Keyboard
SET @max_id = (SELECT id FROM vtiger_crmentity_seq);
SET @p3_exists = (SELECT COUNT(*) FROM vtiger_products WHERE productname = 'Ergonomic Keyboard');
SET @p3_id = @max_id + 1;

INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, modifiedby, setype, createdtime, modifiedtime, viewedtime, presence, deleted, label)
SELECT @p3_id, 1, 1, 1, 'Products', NOW(), NOW(), NOW(), 1, 0, 'Ergonomic Keyboard'
FROM dual WHERE @p3_exists = 0;

INSERT INTO vtiger_products (productid, productname, productcode, product_no, unit_price, qtyinstock, discontinued)
SELECT @p3_id, 'Ergonomic Keyboard', 'EKB-300', 'PRD-SETUP-003', 79.99, 75, 1
FROM dual WHERE @p3_exists = 0;

INSERT INTO vtiger_productcf (productid)
SELECT @p3_id FROM dual WHERE @p3_exists = 0;

UPDATE vtiger_crmentity_seq SET id = IF(@p3_exists = 0, @p3_id, @max_id);
SQLEOF

docker exec -i vtiger-db mysql -u vtiger -pvtiger_pass vtiger < /tmp/setup_quote_prereqs.sql 2>/dev/null

# 3. Ensure logged in and navigate to Quotes module
echo "--- Setting up browser ---"
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Quotes&view=List"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="