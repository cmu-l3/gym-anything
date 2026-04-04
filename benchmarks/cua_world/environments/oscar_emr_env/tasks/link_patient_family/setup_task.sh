#!/bin/bash
# Setup script for Link Patient Family task
# Creates two patients (Mother and Child) and ensures they are NOT linked

echo "=== Setting up Link Patient Family Task ==="

source /workspace/scripts/task_utils.sh

# Define Patients
MOM_FNAME="Priya"
MOM_LNAME="Das"
MOM_DOB="1990-05-15"

SON_FNAME="Leo"
SON_LNAME="Das"
SON_DOB="2023-02-10"

# 1. Create Mother (Priya Das) if not exists
echo "Ensuring patient $MOM_FNAME $MOM_LNAME exists..."
MOM_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$MOM_FNAME' AND last_name='$MOM_LNAME'" | tr -d '[:space:]')

if [ "${MOM_EXISTS:-0}" -eq 0 ]; then
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, year_of_birth, month_of_birth, date_of_birth_day,
        hin, ver, province, address, city, postal, phone,
        patient_status, roster_status, provider_no
    ) VALUES (
        '$MOM_LNAME', '$MOM_FNAME', 'F', '$MOM_DOB', '1990', '05', '15',
        '9384756102', 'AB', 'ON', '123 Oak Avenue', 'Toronto', 'M4C 1B2', '416-555-0100',
        'AC', 'RO', '999998'
    );"
    echo "Created Mother: $MOM_FNAME $MOM_LNAME"
else
    echo "Mother $MOM_FNAME $MOM_LNAME already exists."
fi

# 2. Create Son (Leo Das) if not exists
echo "Ensuring patient $SON_FNAME $SON_LNAME exists..."
SON_EXISTS=$(oscar_query "SELECT COUNT(*) FROM demographic WHERE first_name='$SON_FNAME' AND last_name='$SON_LNAME'" | tr -d '[:space:]')

if [ "${SON_EXISTS:-0}" -eq 0 ]; then
    oscar_query "INSERT INTO demographic (
        last_name, first_name, sex, date_of_birth, year_of_birth, month_of_birth, date_of_birth_day,
        hin, ver, province, address, city, postal, phone,
        patient_status, roster_status, provider_no
    ) VALUES (
        '$SON_LNAME', '$SON_FNAME', 'M', '$SON_DOB', '2023', '02', '10',
        '9384756103', 'AB', 'ON', '123 Oak Avenue', 'Toronto', 'M4C 1B2', '416-555-0100',
        'AC', 'RO', '999998'
    );"
    echo "Created Son: $SON_FNAME $SON_LNAME"
else
    echo "Son $SON_FNAME $SON_LNAME already exists."
fi

# 3. Get IDs for cleaning and verification
MOM_ID=$(get_patient_id "$MOM_FNAME" "$MOM_LNAME")
SON_ID=$(get_patient_id "$SON_FNAME" "$SON_LNAME")

echo "Mother ID: $MOM_ID"
echo "Son ID: $SON_ID"
echo "$MOM_ID" > /tmp/mom_id.txt
echo "$SON_ID" > /tmp/son_id.txt

# 4. Clear any existing links between them (Clean Slate)
echo "Clearing existing links..."
if [ -n "$MOM_ID" ] && [ -n "$SON_ID" ]; then
    # Try multiple potential table names for robustness (schema varies by Oscar version)
    # Common table is `demographic_link` or `link_demographic`
    
    # Check if `link_demographic` exists
    TABLE_CHECK=$(oscar_query "SHOW TABLES LIKE 'link_demographic'")
    if [ -n "$TABLE_CHECK" ]; then
        LINK_TABLE="link_demographic"
    else
        LINK_TABLE="demographic_link" # Fallback
    fi
    
    echo "Using link table: $LINK_TABLE"
    echo "$LINK_TABLE" > /tmp/link_table_name.txt
    
    # Delete links in both directions
    oscar_query "DELETE FROM $LINK_TABLE WHERE (demographic_no='$SON_ID' AND demographic_no_related='$MOM_ID') OR (demographic_no='$MOM_ID' AND demographic_no_related='$SON_ID')"
fi

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Prepare Browser
ensure_firefox_on_oscar

# 7. Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="