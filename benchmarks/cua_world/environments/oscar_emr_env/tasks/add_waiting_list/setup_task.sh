#!/bin/bash
set -e
echo "=== Setting up Add Waiting List task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OSCAR is running and accessible
# ============================================================
wait_for_oscar_http 180

# ============================================================
# 2. Add patient Margaret Wilson if not already present
# ============================================================
echo "Ensuring patient Margaret Wilson exists..."
# Check via SQL
PATIENT_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Margaret' AND last_name='Wilson'" 2>/dev/null || echo "0")

if [ "${PATIENT_EXISTS:-0}" -lt 1 ]; then
    echo "Creating patient Margaret Wilson..."
    # Insert basic demographic record
    oscar_query "
    INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, hin, ver, address,
        city, province, postal, phone, patient_status, roster_status,
        date_joined, chart_no, provider_no, family_doctor, lastUpdateDate
    ) VALUES (
        'Wilson', 'Margaret', 'F', '1958-09-22', '9283746501', 'AB',
        '45 Maple Drive', 'Toronto', 'ON', 'M5V 2T6',
        '416-555-0187', 'AC', 'RO',
        CURDATE(), 'MW-20250122', '999998',
        '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>', NOW()
    );" || echo "Warning: Could not create patient Margaret Wilson"

    # Get the newly created demographic_no
    DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Margaret' AND last_name='Wilson' ORDER BY demographic_no DESC LIMIT 1" 2>/dev/null)
    echo "Created Margaret Wilson with demographic_no: $DEMO_NO"

    # Add required extension table entries to prevent errors when opening chart
    if [ -n "$DEMO_NO" ]; then
        oscar_query "INSERT IGNORE INTO demographicExt (demographic_no, key_val, value) VALUES
            ($DEMO_NO, 'demo_cell', '416-555-0188'),
            ($DEMO_NO, 'aboriginal', ''),
            ($DEMO_NO, 'hPhoneExt', ''),
            ($DEMO_NO, 'wPhoneExt', ''),
            ($DEMO_NO, 'cytolNum', ''),
            ($DEMO_NO, 'phoneComment', '');" 2>/dev/null || true
    fi
else
    echo "Patient Margaret Wilson already exists (count: $PATIENT_EXISTS)"
    DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Margaret' AND last_name='Wilson' ORDER BY demographic_no DESC LIMIT 1" 2>/dev/null)
fi

# Record patient demographic_no for verification/export script
echo "$DEMO_NO" > /tmp/margaret_wilson_demo_no.txt

# ============================================================
# 3. Ensure no pre-existing "Orthopedic Surgery" waiting list
# ============================================================
echo "Cleaning up any pre-existing Orthopedic Surgery waiting list..."
# Delete entries from WaitingList linked to any list with matching name
oscar_query "DELETE FROM WaitingList WHERE waiting_list_name_id IN (SELECT ID FROM WaitingListName WHERE name LIKE '%Orthopedic%Surgery%');" 2>/dev/null || true
# Delete the list name definition itself
oscar_query "DELETE FROM WaitingListName WHERE name LIKE '%Orthopedic%Surgery%';" 2>/dev/null || true

# ============================================================
# 4. Record initial waiting list state for anti-gaming
# ============================================================
echo "Recording initial waiting list state..."
INITIAL_WL_COUNT=$(oscar_query "SELECT COUNT(*) FROM WaitingList" 2>/dev/null || echo "0")
echo "$INITIAL_WL_COUNT" > /tmp/initial_wl_count.txt

INITIAL_WLN_COUNT=$(oscar_query "SELECT COUNT(*) FROM WaitingListName" 2>/dev/null || echo "0")
echo "$INITIAL_WLN_COUNT" > /tmp/initial_wln_count.txt

# ============================================================
# 5. Launch Firefox on OSCAR login page
# ============================================================
echo "Launching Firefox..."
ensure_firefox_on_oscar

sleep 3

# ============================================================
# 6. Take initial screenshot
# ============================================================
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="