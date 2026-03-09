#!/bin/bash
# Setup script for Cancel Provider Schedule task in OSCAR EMR

echo "=== Setting up Cancel Provider Schedule Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OSCAR is ready
wait_for_oscar_http 300

# ============================================================
# 1. Prepare Data: Patients
# ============================================================
echo "Preparing patients..."
# Create 3 dummy patients if they don't exist
# Using direct SQL for speed and reliability
oscar_query "INSERT IGNORE INTO demographic (last_name, first_name, sex, year_of_birth, month_of_birth, date_of_birth, patient_status, lastUpdateDate) VALUES 
('SickPatient', 'One', 'M', '1980', '01', '01', 'AC', NOW()),
('SickPatient', 'Two', 'F', '1985', '05', '05', 'AC', NOW()),
('SickPatient', 'Three', 'M', '1990', '10', '10', 'AC', NOW());"

# Get their demographic IDs
ID1=$(oscar_query "SELECT demographic_no FROM demographic WHERE last_name='SickPatient' AND first_name='One' LIMIT 1")
ID2=$(oscar_query "SELECT demographic_no FROM demographic WHERE last_name='SickPatient' AND first_name='Two' LIMIT 1")
ID3=$(oscar_query "SELECT demographic_no FROM demographic WHERE last_name='SickPatient' AND first_name='Three' LIMIT 1")

echo "Patient IDs: $ID1, $ID2, $ID3"

# ============================================================
# 2. Prepare Data: Provider (oscardoc / 999998)
# ============================================================
# Ensure provider exists (usually done by main setup, but double check)
oscar_query "INSERT IGNORE INTO provider (provider_no, last_name, first_name, provider_type, status) VALUES ('999998', 'Chen', 'Sarah', 'doctor', '1');"

# ============================================================
# 3. Prepare Data: Appointments for Today
# ============================================================
echo "Creating appointments for today..."

# Clear any existing appointments for this provider today to ensure clean state
oscar_query "DELETE FROM appointment WHERE provider_no='999998' AND appointment_date=CURDATE();"

# Insert 3 appointments (09:00, 09:30, 10:00)
# Status 't' = To Do / Pending
# program_id = 0 (default)

# Appointment 1: 09:00 - 09:30
oscar_query "INSERT INTO appointment (demographic_no, provider_no, appointment_date, start_time, end_time, status, reason, program_id, created_date) 
VALUES ('$ID1', '999998', CURDATE(), '09:00:00', '09:30:00', 't', 'Follow-up', 0, NOW());"

# Appointment 2: 09:30 - 10:00
oscar_query "INSERT INTO appointment (demographic_no, provider_no, appointment_date, start_time, end_time, status, reason, program_id, created_date) 
VALUES ('$ID2', '999998', CURDATE(), '09:30:00', '10:00:00', 't', 'Physical Exam', 0, NOW());"

# Appointment 3: 10:00 - 10:30
oscar_query "INSERT INTO appointment (demographic_no, provider_no, appointment_date, start_time, end_time, status, reason, program_id, created_date) 
VALUES ('$ID3', '999998', CURDATE(), '10:00:00', '10:30:00', 't', 'Consultation', 0, NOW());"

# Verify insertion
COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE provider_no='999998' AND appointment_date=CURDATE() AND status='t'")
echo "Created $COUNT active appointments for Dr. Chen."
echo "$COUNT" > /tmp/initial_appt_count

# ============================================================
# 4. Browser Setup
# ============================================================
ensure_firefox_on_oscar

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Appointments created for Today:"
echo "  09:00 - SickPatient One"
echo "  09:30 - SickPatient Two"
echo "  10:00 - SickPatient Three"