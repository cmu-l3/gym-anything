#!/bin/bash
set -e
echo "=== Setting up Correct Billing Claim Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Patient Exists (Maria Santos)
echo "Ensuring patient Maria Santos exists..."
PATIENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Maria' AND last_name='Santos'" || echo "0")
if [ "${PATIENT_COUNT:-0}" -eq 0 ]; then
    echo "Seeding Maria Santos..."
    oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, city, province, postal, phone, provider_no, hin, hc_type, patient_status, lastUpdateDate) VALUES ('Santos', 'Maria', 'F', '1978', '06', '22', 'Toronto', 'ON', 'M5V 2T6', '416-555-0199', '999998', '6854321098', 'ON', 'AC', NOW());" 2>/dev/null || true
fi

# 2. Inject the "Rejected" Billing Claim
echo "Injecting rejected billing claim..."

# We use a temporary SQL script to handle variables and return the ID
cat > /tmp/inject_bill.sql << EOF
SET @pat_id = (SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1);
SET @prov_no = '999998';
-- Service date is yesterday
SET @svc_date = DATE_SUB(CURDATE(), INTERVAL 1 DAY);

-- Insert Master Record (Status 'E' for Error)
INSERT INTO billing_master (
    demographic_no, provider_no, billing_date, service_date, 
    amount, billing_type, status, created_date, lastUpdateDate
) VALUES (
    @pat_id, @prov_no, NOW(), @svc_date, 
    33.70, 'OHIP', 'E', NOW(), NOW()
);

SET @master_id = LAST_INSERT_ID();

-- Insert Item Record (Wrong Diagnosis '999')
INSERT INTO billing_item (
    billing_master_id, service_code, diagnosis_code, service_date, 
    quantity, service_description, fee
) VALUES (
    @master_id, 'A007', '999', @svc_date, 
    1, 'Intermediate Assessment', 33.70
);

-- Output the ID for the setup script to capture
SELECT @master_id;
EOF

# Execute and capture the ID
BILL_ID=$(docker exec -i oscar-db mysql -u oscar -poscar oscar -N < /tmp/inject_bill.sql 2>/dev/null | tail -n 1)

if [ -n "$BILL_ID" ] && [ "$BILL_ID" != "NULL" ]; then
    echo "Injected Billing ID: $BILL_ID"
    echo "$BILL_ID" > /tmp/target_bill_id.txt
else
    echo "ERROR: Failed to inject billing record or retrieve ID."
    exit 1
fi

# 3. Clean up any other potential duplicates for clarity (optional but good for stability)
# (Skipped to avoid deleting user history, trusting ID tracking)

# 4. Open Firefox
ensure_firefox_on_oscar

# 5. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Bill ID: $BILL_ID"