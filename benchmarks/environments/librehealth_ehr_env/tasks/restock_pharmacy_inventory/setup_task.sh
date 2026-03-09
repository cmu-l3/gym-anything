#!/bin/bash
echo "=== Setting up Restock Pharmacy Inventory Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure LibreHealth is running
wait_for_librehealth 60

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure the Drug Exists
# We check if 'Simvastatin 20mg' exists. If not, we insert it.
# We set stock to 0 or a low number to ensure the addition is noticeable.
DRUG_NAME="Simvastatin 20mg"
DRUG_CHECK=$(librehealth_query "SELECT drug_id FROM drugs WHERE name='${DRUG_NAME}' LIMIT 1")

if [ -z "$DRUG_CHECK" ]; then
    echo "Creating drug record for ${DRUG_NAME}..."
    # Insert basic drug record. Schema: drug_id, name, ndc_number, form, size, unit, route
    librehealth_query "INSERT INTO drugs (name, ndc_number, form, size, unit, route) VALUES ('${DRUG_NAME}', '55555-0020-01', '1', '20', 'mg', '1')"
    DRUG_ID=$(librehealth_query "SELECT drug_id FROM drugs WHERE name='${DRUG_NAME}' LIMIT 1")
    echo "Created Drug ID: $DRUG_ID"
else
    DRUG_ID="$DRUG_CHECK"
    echo "Drug exists: $DRUG_ID"
fi

# Ensure specific vendor exists in address book (users table or similar depending on implementation, 
# but usually Inventory allows text entry or requires a vendor from address book).
# We'll insert a vendor into the address book/users just in case the UI enforces selection.
VENDOR_NAME="PharmaDistro Inc"
# LibreHealth/OpenEMR stores vendors in users table with authorized=0 or similar, or sometimes just text in inventory transactions.
# We won't force it, but good to have context.

# 4. Record Initial State
INITIAL_STOCK=$(librehealth_query "SELECT stock_level FROM drugs WHERE drug_id='${DRUG_ID}'" 2>/dev/null || echo "0")
# If null, treat as 0
if [ -z "$INITIAL_STOCK" ] || [ "$INITIAL_STOCK" = "NULL" ]; then INITIAL_STOCK=0; fi
echo "$INITIAL_STOCK" > /tmp/initial_stock_level.txt
echo "Initial Stock Level: $INITIAL_STOCK"

# 5. Launch Firefox
# Start at the Login page. Agent must navigate to Inventory.
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# 6. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="