#!/bin/bash
set -e
echo "=== Setting up Clinical Trial Cohort Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Ensure MedinTux database exists and has data
# We rely on the standard install, but let's verify count
PATIENT_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom" 2>/dev/null || echo "0")
echo "Initial patient count in DB: $PATIENT_COUNT" > /tmp/initial_db_count.txt

# If DB is empty (unlikely with standard install but good for robustness), inject a few sample records
if [ "$PATIENT_COUNT" -lt 5 ]; then
    echo "Injecting sample patients..."
    # Insert a mix of eligible and ineligible patients
    # 1. Eligible (Age ~40)
    insert_patient "$(cat /proc/sys/kernel/random/uuid)" "TEST_ELIGIBLE" "Jean" "1984-01-01" "M" "M." "1 Rue Test" "75000" "Paris" "0102030405" "1840175000001"
    # 2. Too Young (Age ~20)
    insert_patient "$(cat /proc/sys/kernel/random/uuid)" "TEST_YOUNG" "Marie" "2004-01-01" "F" "Mme" "2 Rue Test" "75000" "Paris" "0602030405" "2040175000002"
    # 3. Too Old (Age ~80)
    insert_patient "$(cat /proc/sys/kernel/random/uuid)" "TEST_OLD" "Pierre" "1940-01-01" "M" "M." "3 Rue Test" "75000" "Paris" "0702030405" "1400175000003"
fi

# Clear output directory
rm -f /home/ga/Documents/cohort_dm2_oral_2024.csv
rm -f /home/ga/Documents/cohort_summary_dm2_oral_2024.txt

# Launch MedinTux Manager for visual context (agent might explore UI to understand schema implied by UI)
# We don't strictly need it for SQL task, but it provides the "Starting State: MedinTux Manager is launched"
launch_medintux_manager

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="