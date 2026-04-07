#!/bin/bash
echo "=== Setting up generate_quote_msa_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "Injecting target Account and Quote data into Vtiger database..."

# Safely inject Account and Quote via SQL to guarantee perfect starting state
# 1. Generate new CRM IDs
ACCT_ID=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "UPDATE vtiger_crmentity_seq SET id=id+1; SELECT id FROM vtiger_crmentity_seq;")
QUOT_ID=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "UPDATE vtiger_crmentity_seq SET id=id+1; SELECT id FROM vtiger_crmentity_seq;")
PROD_ID=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "UPDATE vtiger_crmentity_seq SET id=id+1; SELECT id FROM vtiger_crmentity_seq;")

# 2. Insert Account "Global Tech Industries"
docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -e "
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($ACCT_ID, 1, 1, 'Accounts', NOW(), NOW(), 1, 0, 'Global Tech Industries');
INSERT INTO vtiger_account (accountid, accountname) VALUES ($ACCT_ID, 'Global Tech Industries');
INSERT INTO vtiger_accountbillads (accountaddressid) VALUES ($ACCT_ID);
INSERT INTO vtiger_accountshipads (accountaddressid) VALUES ($ACCT_ID);
INSERT INTO vtiger_accountscf (accountid) VALUES ($ACCT_ID);
"

# 3. Insert Quote "Q-Enterprise Server Deployment"
# Get the next quote sequence number
QUOT_NO=$(docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -N -e "UPDATE vtiger_modentity_num SET cur_id=cur_id+1 WHERE semodule='Quotes'; SELECT CONCAT(prefix, cur_id-1) FROM vtiger_modentity_num WHERE semodule='Quotes';")
if [ -z "$QUOT_NO" ]; then QUOT_NO="QUO3"; fi

docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -e "
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($QUOT_ID, 1, 1, 'Quotes', NOW(), NOW(), 1, 0, 'Q-Enterprise Server Deployment');
INSERT INTO vtiger_quotes (quoteid, quote_no, subject, quotestage, accountid, total, subtotal, pre_tax_total, taxtype, currency_id) VALUES ($QUOT_ID, '$QUOT_NO', 'Q-Enterprise Server Deployment', 'Created', $ACCT_ID, 15400.00, 15400.00, 15400.00, 'group', 1);
INSERT INTO vtiger_quotescf (quoteid) VALUES ($QUOT_ID);
"

# 4. Insert dummy Product and link it so the Quote has a valid total line item
docker exec vtiger-db mysql -u vtiger -pvtiger_pass vtiger -e "
INSERT INTO vtiger_crmentity (crmid, smcreatorid, smownerid, setype, createdtime, modifiedtime, presence, deleted, label) VALUES ($PROD_ID, 1, 1, 'Products', NOW(), NOW(), 1, 0, 'Enterprise Server Setup');
INSERT INTO vtiger_products (productid, productname, unit_price) VALUES ($PROD_ID, 'Enterprise Server Setup', 15400.00);
INSERT INTO vtiger_productcf (productid) VALUES ($PROD_ID);
INSERT INTO vtiger_inventoryproductrel (id, productid, sequence_no, quantity, listprice, lineitem_id) VALUES ($QUOT_ID, $PROD_ID, 1, 1.00, 15400.00, 1);
"
echo "Injected Quote: $QUOT_NO for Account: Global Tech Industries"

# Create the Master Service Agreement text template for the agent
mkdir -p /home/ga/Documents
cat << 'EOF' > /home/ga/Documents/Master_Service_Agreement_Template.txt
MASTER SERVICE AGREEMENT

This Master Service Agreement ("Agreement") is entered into by and between Vtiger Solutions and [ORGANIZATION NAME] ("Client").

1. SERVICES PROVIDED
Provider agrees to deliver the hardware and deployment services as outlined in Quote #[QUOTE NUMBER].

2. COMPENSATION
The total compensation for the services and hardware under this agreement is strictly limited to [GRAND TOTAL]. All payments are due within 30 days of invoice.

3. TERMS & CONDITIONS
This agreement shall be governed by the laws of the State of California. The parties agree to the binding arbitration of any disputes.

Signed,
___________________________
Authorized Representative
EOF
chmod 666 /home/ga/Documents/Master_Service_Agreement_Template.txt

# Ensure Firefox is open and logged into Vtiger CRM (navigate to dashboard)
ensure_vtiger_logged_in "http://localhost:8000/index.php"
sleep 2

# Take initial screenshot to prove starting state
take_screenshot /tmp/msa_task_initial.png

echo "=== Task setup complete ==="