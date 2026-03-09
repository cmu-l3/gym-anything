#!/bin/bash
set -e
echo "=== Setting up Record Measurements Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# ============================================================
# 1. Ensure OSCAR is running and accessible
# ============================================================
wait_for_oscar_http 300

# ============================================================
# 2. Create patient Gloria Vargas if she doesn't exist
# ============================================================
echo "Creating patient Gloria Vargas..."

# Find next available demographic_no
NEXT_DEMO=$(oscar_query "SELECT COALESCE(MAX(demographic_no), 0) + 1 FROM demographic")
echo "Using demographic_no: $NEXT_DEMO"

# Check if patient already exists
EXISTING=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='Gloria' AND last_name='Vargas' AND year_of_birth='1958'")

if [ "${EXISTING:-0}" -gt 0 ]; then
    echo "Patient Gloria Vargas already exists"
    DEMO_NO=$(oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Gloria' AND last_name='Vargas' AND year_of_birth='1958' LIMIT 1")
else
    DEMO_NO=$NEXT_DEMO
    oscar_query "INSERT INTO demographic (
        demographic_no, last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth,
        address, city, province, postal, phone, email,
        hin, ver, roster_status, patient_status, date_joined, chart_no,
        provider_no, family_doctor
    ) VALUES (
        $DEMO_NO, 'Vargas', 'Gloria', 'F', '1958', '04', '22',
        '145 Dundas Street West', 'Toronto', 'ON', 'M5G1C7', '416-555-0198', 'gloria.vargas@email.com',
        '2847561093', 'AB', 'RO', 'AC', CURDATE(), 'GV-${DEMO_NO}',
        '999998', '<rdohip>999998</rdohip><rd>Dr. Sarah Chen</rd>'
    )"
    echo "Created patient Gloria Vargas with demographic_no=$DEMO_NO"
fi

# Save demographic_no for export/verification
echo "$DEMO_NO" > /tmp/task_patient_demo_no.txt
echo "Patient demographic_no: $DEMO_NO"

# ============================================================
# 3. Record initial measurement count for this patient
# ============================================================
INITIAL_MEAS_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$DEMO_NO'" 2>/dev/null || echo "0")
echo "$INITIAL_MEAS_COUNT" > /tmp/initial_measurement_count.txt
echo "Initial measurement count for patient: $INITIAL_MEAS_COUNT"

# ============================================================
# 4. Add some historical measurements to make the flowsheet realistic
#    (Gloria has been a patient for 2 years with diabetes)
# ============================================================
echo "Adding historical measurements for realism..."

# 6 months ago
oscar_query "INSERT IGNORE INTO measurements (type, demographicNo, providerNo, dataField, measuringInstruction, dateObserved, dateEntered)
VALUES
('A1C', '$DEMO_NO', '999998', '7.8', '%', DATE_SUB(CURDATE(), INTERVAL 6 MONTH), DATE_SUB(CURDATE(), INTERVAL 6 MONTH)),
('WAIS', '$DEMO_NO', '999998', '91', 'cm', DATE_SUB(CURDATE(), INTERVAL 6 MONTH), DATE_SUB(CURDATE(), INTERVAL 6 MONTH)),
('BMI', '$DEMO_NO', '999998', '28.1', 'kg/m2', DATE_SUB(CURDATE(), INTERVAL 6 MONTH), DATE_SUB(CURDATE(), INTERVAL 6 MONTH)),
('GLUC', '$DEMO_NO', '999998', '9.2', 'mmol/L', DATE_SUB(CURDATE(), INTERVAL 6 MONTH), DATE_SUB(CURDATE(), INTERVAL 6 MONTH))" 2>/dev/null || true

# 12 months ago
oscar_query "INSERT IGNORE INTO measurements (type, demographicNo, providerNo, dataField, measuringInstruction, dateObserved, dateEntered)
VALUES
('A1C', '$DEMO_NO', '999998', '8.1', '%', DATE_SUB(CURDATE(), INTERVAL 12 MONTH), DATE_SUB(CURDATE(), INTERVAL 12 MONTH)),
('WAIS', '$DEMO_NO', '999998', '93', 'cm', DATE_SUB(CURDATE(), INTERVAL 12 MONTH), DATE_SUB(CURDATE(), INTERVAL 12 MONTH)),
('BMI', '$DEMO_NO', '999998', '28.9', 'kg/m2', DATE_SUB(CURDATE(), INTERVAL 12 MONTH), DATE_SUB(CURDATE(), INTERVAL 12 MONTH)),
('GLUC', '$DEMO_NO', '999998', '10.1', 'mmol/L', DATE_SUB(CURDATE(), INTERVAL 12 MONTH), DATE_SUB(CURDATE(), INTERVAL 12 MONTH))" 2>/dev/null || true

echo "Historical measurements added"

# Update initial count after seeding historical data (so we only count what agent adds)
INITIAL_MEAS_COUNT_AFTER=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$DEMO_NO'" 2>/dev/null || echo "0")
echo "$INITIAL_MEAS_COUNT_AFTER" > /tmp/initial_measurement_count.txt
echo "Measurement count after historical seeding: $INITIAL_MEAS_COUNT_AFTER"

# ============================================================
# 5. Launch Firefox on OSCAR login page
# ============================================================
echo "Launching Firefox on OSCAR login page..."
ensure_firefox_on_oscar

sleep 3

# ============================================================
# 6. Take initial screenshot
# ============================================================
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="