#!/bin/bash
# Setup script for Create Tickler Reminder task
set -e

echo "=== Setting up Create Tickler Reminder Task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# 1. Ensure patient Maria Santos exists
# ============================================================
echo "Ensuring patient Maria Santos exists..."

# Check if she already exists
EXISTING=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Maria' AND last_name='Santos'" 2>/dev/null || echo "0")

if [ "${EXISTING:-0}" -lt 1 ]; then
    echo "Creating patient Maria Santos..."
    oscar_query "
    INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, hin, ver,
        address, city, province, postal, phone,
        patient_status, date_joined, chart_no,
        roster_status, family_doctor, provider_no,
        end_date, ef_id, patient_status_date, lastUpdateDate
    ) VALUES (
        'Santos', 'Maria', 'F', '1978-06-12', '6834729105', 'AB',
        '45 Dundas Street W', 'Toronto', 'ON', 'M5G1Z8', '416-555-0198',
        'AC', CURDATE(), '',
        'RO', '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>', '999998',
        '0001-01-01', '', CURDATE(), NOW()
    );"
    echo "Patient Maria Santos created."
fi

# Get her demographic_no
MARIA_DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
echo "$MARIA_DEMO_NO" > /tmp/maria_demo_no.txt
echo "Patient ID: $MARIA_DEMO_NO"

# ============================================================
# 2. Clean up old ticklers for this patient (Clean State)
# ============================================================
echo "Cleaning up previous ticklers..."
oscar_query "DELETE FROM tickler WHERE demographic_no='$MARIA_DEMO_NO'" 2>/dev/null || true

# Record initial count (should be 0)
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM tickler WHERE demographic_no='$MARIA_DEMO_NO'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_tickler_count.txt

# ============================================================
# 3. Calculate Target Date (for verification reference)
# ============================================================
TARGET_DATE=$(date -d "+14 days" +%Y-%m-%d)
echo "$TARGET_DATE" > /tmp/target_date.txt
echo "Target service date (14 days out): $TARGET_DATE"

# ============================================================
# 4. Prepare Application
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="