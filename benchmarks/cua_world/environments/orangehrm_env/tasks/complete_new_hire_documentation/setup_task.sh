#!/bin/bash
set -e
echo "=== Setting up complete_new_hire_documentation task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory and dummy files
DOCS_DIR="/home/ga/Documents/HR_Docs"
mkdir -p "$DOCS_DIR"

# Generate a dummy profile photo (blue square)
convert -size 400x400 xc:cornflowerblue \
    -fill white -pointsize 40 -gravity center -draw "text 0,0 'James'" \
    "$DOCS_DIR/james_photo.jpg"

# Generate dummy PDFs
convert -size 595x842 xc:white \
    -fill black -pointsize 24 -gravity north -draw "text 0,50 'OFFER LETTER'" \
    -draw "text 0,100 'Confidential Employment Offer'" \
    "$DOCS_DIR/signed_offer.pdf"

convert -size 595x842 xc:white \
    -fill black -pointsize 24 -gravity north -draw "text 0,50 'NON-DISCLOSURE AGREEMENT'" \
    -draw "text 0,100 'Confidentiality Terms'" \
    "$DOCS_DIR/nda_signed.pdf"

# Set permissions so 'ga' user can access/upload them
chown -R ga:ga "/home/ga/Documents"

# 2. Ensure Database State
wait_for_http "$ORANGEHRM_URL" 60

# Check if James Anderson exists; if not, create him
EMP_FIRST="James"
EMP_LAST="Anderson"
EMP_ID="EMP_JA_001"

EXISTING_COUNT=$(orangehrm_db_query "SELECT COUNT(*) FROM hs_hr_employee WHERE emp_firstname='$EMP_FIRST' AND emp_lastname='$EMP_LAST' AND purged_at IS NULL;" 2>/dev/null | tr -d '[:space:]')

if [ "$EXISTING_COUNT" -eq "0" ]; then
    log "Creating employee $EMP_FIRST $EMP_LAST..."
    # Insert basic employee record
    orangehrm_db_query "INSERT INTO hs_hr_employee (emp_firstname, emp_lastname, employee_id, emp_status) VALUES ('$EMP_FIRST', '$EMP_LAST', '$EMP_ID', 1);"
fi

# Get the emp_number (auto-increment primary key)
EMP_NUMBER=$(get_employee_empnum "$EMP_FIRST" "$EMP_LAST")
log "James Anderson emp_number: $EMP_NUMBER"
echo "$EMP_NUMBER" > /tmp/target_emp_number.txt

# 3. Clean State: Remove existing pictures and attachments for this employee
log "Clearing existing documents for emp_number $EMP_NUMBER..."
orangehrm_db_query "DELETE FROM hs_hr_emp_picture WHERE emp_number = $EMP_NUMBER;"
orangehrm_db_query "DELETE FROM hs_hr_emp_attachment WHERE emp_number = $EMP_NUMBER;"

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
# Initial count of attachments should be 0
echo "0" > /tmp/initial_attachment_count.txt

# 5. Launch Firefox and Login
ensure_orangehrm_logged_in "${ORANGEHRM_URL}/web/index.php/dashboard/index"

# 6. Capture Evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Files created in $DOCS_DIR"
echo "Employee: $EMP_FIRST $EMP_LAST (ID: $EMP_NUMBER)"