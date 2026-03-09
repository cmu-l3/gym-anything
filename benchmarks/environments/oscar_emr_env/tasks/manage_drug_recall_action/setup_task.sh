#!/bin/bash
set -e
echo "=== Setting up Manage Drug Recall Action task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OSCAR is ready
# ============================================================
wait_for_oscar_http 300

# ============================================================
# 2. Ensure Target Patient Exists (Maria Santos)
# ============================================================
echo "Ensuring patient Maria Santos exists..."
# We use a specific ID (501) to easily link the drug record later
docker exec oscar-db mysql -u oscar -poscar oscar -e \
    "INSERT IGNORE INTO demographic (demographic_no, last_name, first_name, year_of_birth, month_of_birth, date_of_birth, sex, patient_status, roster_status, phone, address, city, province, postal, hin) 
     VALUES (501, 'Santos', 'Maria', '1978', '06', '1978-06-22', 'F', 'AC', 'RO', '416-555-0193', '45 Dundas Street West', 'Toronto', 'ON', 'M5G 1Z8', '6839472581');" 2>/dev/null

# ============================================================
# 3. Seed 'Atenolol' Prescription
# ============================================================
# We need to insert a record into the 'drugs' table so the search finds it.
# Dates: Rx 2 months ago, active for 3 months.
RX_DATE=$(date -d "60 days ago" '+%Y-%m-%d')
START_DATE=$(date -d "60 days ago" '+%Y-%m-%d')
END_DATE=$(date -d "30 days from now" '+%Y-%m-%d')

echo "Seeding Atenolol prescription for patient Maria Santos (ID 501)..."

# Clean up any existing Atenolol records for this patient to ensure clean state
docker exec oscar-db mysql -u oscar -poscar oscar -e \
    "DELETE FROM drugs WHERE demographic_no='501' AND drug_name LIKE '%Atenolol%';"

# Insert the active prescription
# provider_no '999998' is typically the default oscardoc/scheduler provider
docker exec oscar-db mysql -u oscar -poscar oscar -e \
    "INSERT INTO drugs (demographic_no, provider_no, rx_date, start_date, end_date, drug_name, dosage, duration, duration_unit, quantity, repeats, freqCode, route, special_instruction, archived, written_date)
     VALUES ('501', '999998', '$RX_DATE', '$START_DATE', '$END_DATE', 'Atenolol 50mg', '50', '90', 'D', '90', '3', 'QD', 'PO', 'Take once daily', 0, '$RX_DATE');"

# ============================================================
# 4. Record Initial Tickler State
# ============================================================
# Count how many ticklers Maria already has (should be 0 usually)
INITIAL_TICKLERS=$(oscar_query "SELECT COUNT(*) FROM tickler WHERE demographic_no='501'" || echo "0")
echo "$INITIAL_TICKLERS" > /tmp/initial_tickler_count.txt

# ============================================================
# 5. Launch Firefox
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="