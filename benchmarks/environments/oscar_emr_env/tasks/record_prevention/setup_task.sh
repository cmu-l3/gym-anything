#!/bin/bash
set -e
echo "=== Setting up record_prevention task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure patient Maria Santos exists
# ============================================================
echo "Ensuring patient Maria Santos exists..."

# Check if patient exists
PATIENT_ID=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1" | tr -d '[:space:]')

if [ -z "$PATIENT_ID" ]; then
    echo "Creating patient Maria Santos..."
    # Get next available ID
    NEXT_DEMO=$(oscar_query "SELECT COALESCE(MAX(demographic_no), 0) + 1 FROM demographic" | tr -d '[:space:]')
    
    oscar_query "INSERT INTO demographic (
        demographic_no, first_name, last_name, sex, date_of_birth,
        hin, ver, province, address, city, postal, phone,
        patient_status, roster_status, date_joined,
        family_doctor, year_of_birth, month_of_birth,
        chart_no, official_lang, spoken_lang, province_hc_ver
    ) VALUES (
        $NEXT_DEMO, 'Maria', 'Santos', 'F', '1978-06-22',
        '6839472581', 'JK', 'ON', '45 Dundas Street West', 'Toronto', 'M5G1Z8', '416-555-0193',
        'AC', 'RO', CURDATE(),
        '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>', '1978', '06',
        '', 'English', 'English', ''
    )" 2>/dev/null
    PATIENT_ID=$NEXT_DEMO
fi

echo "$PATIENT_ID" > /tmp/maria_santos_demo_no.txt
echo "Patient ID: $PATIENT_ID"

# ============================================================
# 2. Clean prior Flu records for this patient (Clean Slate)
# ============================================================
echo "Cleaning prior Flu records..."
PREV_IDS=$(oscar_query "SELECT id FROM preventions WHERE demographic_no=$PATIENT_ID AND prevention_type='Flu'" 2>/dev/null | tr '\n' ',' | sed 's/,$//')

if [ -n "$PREV_IDS" ]; then
    oscar_query "DELETE FROM preventionsExt WHERE prevention_id IN ($PREV_IDS)" 2>/dev/null || true
    oscar_query "DELETE FROM preventions WHERE id IN ($PREV_IDS)" 2>/dev/null || true
    echo "Removed $(echo "$PREV_IDS" | tr ',' '\n' | wc -l) existing records."
fi

# Record initial count (should be 0 now)
INITIAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM preventions WHERE demographic_no=$PATIENT_ID AND prevention_type='Flu'" | tr -d '[:space:]')
echo "$INITIAL_COUNT" > /tmp/initial_flu_count.txt

# ============================================================
# 3. Setup Browser
# ============================================================
echo "Launching Firefox..."
ensure_firefox_on_oscar

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="