#!/bin/bash
# Setup script for Generate Billing Report task
# Inserts specific billing records (Targets and Distractors) into OSCAR database

echo "=== Setting up Generate Billing Report Task ==="

source /workspace/scripts/task_utils.sh

# 1. Configuration
PROVIDER_NO="999998"  # oscardoc / Dr. Sarah Chen
OTHER_PROVIDER_NO="999999" # Dr. Test (Distractor provider)
TARGET_CODE="K013"
DISTRACTOR_CODE="A007"

# Clean up previous output
rm -f /home/ga/Documents/K013_Report.* 2>/dev/null || true
mkdir -p /home/ga/Documents

# 2. Get a valid patient (Demographic No)
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE patient_status='AC' LIMIT 1")
if [ -z "$PATIENT_ID" ]; then
    echo "No active patient found, seeding one..."
    oscar_query "INSERT INTO demographic (last_name, first_name, sex, date_of_birth, patient_status) VALUES ('Billing', 'Test', 'M', '1980-01-01', 'AC');"
    PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE last_name='Billing' LIMIT 1")
fi
echo "Using Patient ID: $PATIENT_ID"

# 3. Determine dates (Current Month)
CURRENT_DATE=$(date +%Y-%m-%d)
YEAR_MONTH=$(date +%Y-%m)
DAY=$(date +%d)

# 4. Generate Billing Records via SQL
# We need to insert into billing_master (header) and billing_item (services)
# Schema assumptions based on OSCAR:
# billing_master: id (auto), demographic_no, provider_no, billing_date, status, ...
# billing_item: id (auto), billing_master_id, service_code, service_date, ...

echo "Generating billing data..."

# Function to insert a bill
insert_bill() {
    local prov="$1"
    local code="$2"
    local day_offset="$3" # Days ago
    local label="$4"      # "TARGET" or "DISTRACTOR"
    
    # Calculate date
    local bill_date=$(date -d "$day_offset days ago" +%Y-%m-%d)
    
    # Insert Master
    oscar_query "INSERT INTO billing_master (demographic_no, provider_no, billing_date, status, creation_date) VALUES ('$PATIENT_ID', '$prov', '$bill_date', 'B', NOW());"
    
    # Get the ID of the inserted master record
    local master_id=$(oscar_query "SELECT MAX(billing_master_id) FROM billing_master WHERE demographic_no='$PATIENT_ID' AND provider_no='$prov'")
    
    if [ -n "$master_id" ] && [ "$master_id" != "NULL" ]; then
        # Insert Item
        oscar_query "INSERT INTO billing_item (billing_master_id, service_code, service_date) VALUES ('$master_id', '$code', '$bill_date');"
        
        # Log for verification
        echo "$label,$master_id,$prov,$code,$bill_date" >> /tmp/billing_ground_truth.csv
        echo "Inserted $label bill: ID=$master_id Code=$code Prov=$prov Date=$bill_date"
    else
        echo "Error creating billing_master for $label"
    fi
}

# Clear ground truth file
echo "type,invoice_id,provider,code,date" > /tmp/billing_ground_truth.csv

# INSERT TARGETS (Dr. Chen, K013, This Month)
# Ensure we pick days within the current month
insert_bill "$PROVIDER_NO" "$TARGET_CODE" "1" "TARGET"
insert_bill "$PROVIDER_NO" "$TARGET_CODE" "3" "TARGET"
insert_bill "$PROVIDER_NO" "$TARGET_CODE" "5" "TARGET"

# INSERT DISTRACTORS (Dr. Chen, A007, This Month) - Same provider, wrong code
insert_bill "$PROVIDER_NO" "$DISTRACTOR_CODE" "2" "DISTRACTOR_CODE"
insert_bill "$PROVIDER_NO" "$DISTRACTOR_CODE" "4" "DISTRACTOR_CODE"

# INSERT DISTRACTORS (Other Doc, K013, This Month) - Wrong provider, same code
insert_bill "$OTHER_PROVIDER_NO" "$TARGET_CODE" "1" "DISTRACTOR_PROVIDER"

# INSERT DISTRACTORS (Dr. Chen, K013, OLD Date) - Same provider/code, wrong date (2 months ago)
# Note: This checks date filtering. '65 days ago' is safely previous month or earlier.
insert_bill "$PROVIDER_NO" "$TARGET_CODE" "65" "DISTRACTOR_DATE"

# 5. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 6. Launch App
ensure_firefox_on_oscar

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "Setup Complete. Ground Truth:"
cat /tmp/billing_ground_truth.csv