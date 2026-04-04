#!/bin/bash
set -e
echo "=== Setting up Create Prescription Favorite task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OSCAR is running
# ============================================================
wait_for_oscar_http 300

# ============================================================
# 2. Setup Patient "Mario Rossi"
# ============================================================
echo "Ensuring patient Mario Rossi exists..."
if ! patient_exists "Mario" "Rossi"; then
    echo "Creating patient Mario Rossi..."
    # Insert patient directly into DB (using fallback if clean install)
    docker exec oscar-db mysql -u oscar -poscar oscar -e \
    "INSERT INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth_day, date_of_birth, patient_status, provider_no, city, province) 
     VALUES ('Rossi', 'Mario', 'M', '1980', '05', '12', '1980-05-12', 'AC', '999998', 'Toronto', 'ON');"
else
    echo "Patient Mario Rossi already exists."
fi

# ============================================================
# 3. Clean up existing favorites for this task (Idempotency)
# ============================================================
echo "Cleaning up any existing 'Strep Throat' favorites for oscardoc..."
# Clean by template_name (favorite name) or instructions to ensure a clean slate
# provider_no 999998 is oscardoc
docker exec oscar-db mysql -u oscar -poscar oscar -e \
"DELETE FROM drug_template WHERE provider_no='999998' AND (template_name LIKE '%Strep%' OR instructions LIKE '%three times daily%');" 2>/dev/null || true

# ============================================================
# 4. Record Initial State
# ============================================================
# Count existing favorites for provider 999998
INITIAL_COUNT=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e \
"SELECT COUNT(*) FROM drug_template WHERE provider_no='999998'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_fav_count.txt
echo "Initial favorite count: $INITIAL_COUNT"

# ============================================================
# 5. Launch Firefox
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="