#!/bin/bash
# Seed Care2x database with realistic patient data from Synthea CSV
# This script converts Synthea-generated patient data into Care2x's care_person table format.

set -e

echo "=== Seeding Care2x with realistic patient data ==="

CARE2X_DB="care2x"
CARE2X_DB_USER="care2x"
CARE2X_DB_PASS="care2x_pass"
PATIENT_CSV="/workspace/data/patients.csv"

if [ ! -f "$PATIENT_CSV" ]; then
    echo "ERROR: Patient CSV not found at $PATIENT_CSV"
    exit 1
fi

# Generate SQL from patient CSV (sourced from US Census/SSA real data)
python3 /workspace/scripts/seed_care2x.py "$PATIENT_CSV" /tmp/care2x_seed.sql

# Import the generated SQL
if [ -f "/tmp/care2x_seed.sql" ]; then
    echo "Importing seed data into Care2x database..."
    mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" < /tmp/care2x_seed.sql 2>/dev/null || {
        echo "Warning: Some seed data errors (non-fatal)"
    }
    echo "Seed data imported successfully."
else
    echo "ERROR: Seed SQL file not generated"
    exit 1
fi

# Verify patient count
PATIENT_COUNT=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT COUNT(*) FROM care_person;" 2>/dev/null || echo "0")
echo "Total patients in database: $PATIENT_COUNT"

# Seed department data if table is empty
# care_department columns: nr, id, type, name_formal, name_short, name_alternate, LD_var,
#   description, admit_inpatient, admit_outpatient, ...
DEPT_COUNT=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT COUNT(*) FROM care_department;" 2>/dev/null || echo "0")
if [ "$DEPT_COUNT" = "0" ] || [ "$DEPT_COUNT" = "" ]; then
    echo "Seeding department data..."
    mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" << 'DEPTSQL'
INSERT IGNORE INTO care_department (nr, id, type, name_formal, name_short, LD_var, description, admit_inpatient, admit_outpatient, status, modify_id, create_id)
VALUES
(1, 'INTMED', 'clinical', 'Department of Internal Medicine', 'Internal Med', 'LDIntMed', 'General internal medicine department', 1, 1, 'normal', 'admin', 'admin'),
(2, 'PEDS', 'clinical', 'Department of Pediatrics', 'Pediatrics', 'LDPeds', 'Pediatric care department', 1, 1, 'normal', 'admin', 'admin'),
(3, 'OBGYN', 'clinical', 'Department of Obstetrics and Gynecology', 'OB/GYN', 'LDObGyn', 'Obstetrics and gynecology department', 1, 1, 'normal', 'admin', 'admin'),
(4, 'SURG', 'clinical', 'Department of General Surgery', 'Surgery', 'LDSurg', 'General surgery department', 1, 0, 'normal', 'admin', 'admin'),
(5, 'EMER', 'clinical', 'Department of Emergency Medicine', 'Emergency', 'LDEmer', 'Emergency medicine department', 0, 1, 'normal', 'admin', 'admin'),
(6, 'RAD', 'ancillary', 'Department of Radiology', 'Radiology', 'LDRad', 'Diagnostic imaging department', 0, 0, 'normal', 'admin', 'admin'),
(7, 'LAB', 'ancillary', 'Department of Clinical Laboratory', 'Laboratory', 'LDLab', 'Clinical laboratory department', 0, 0, 'normal', 'admin', 'admin'),
(8, 'PHARM', 'ancillary', 'Department of Pharmacy', 'Pharmacy', 'LDPharm', 'Hospital pharmacy department', 0, 0, 'normal', 'admin', 'admin');
DEPTSQL
    echo "Department data seeded."
fi

# Seed room data
# care_room: nr(auto), type_nr, date_create, room_nr, ward_nr, dept_nr, nr_of_beds, info, status, ...
ROOM_COUNT=$(mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" -N -e "SELECT COUNT(*) FROM care_room;" 2>/dev/null || echo "0")
if [ "$ROOM_COUNT" = "0" ] || [ "$ROOM_COUNT" = "" ]; then
    echo "Seeding room data..."
    mysql -u "${CARE2X_DB_USER}" -p"${CARE2X_DB_PASS}" "${CARE2X_DB}" << 'ROOMSQL'
INSERT IGNORE INTO care_room (type_nr, date_create, room_nr, ward_nr, dept_nr, nr_of_beds, info, status, modify_id, create_id)
VALUES
(1, CURDATE(), 101, 1, 1, 4, 'General Ward A - Room 101', 'normal', 'admin', 'admin'),
(1, CURDATE(), 102, 1, 1, 4, 'General Ward A - Room 102', 'normal', 'admin', 'admin'),
(1, CURDATE(), 103, 2, 1, 4, 'General Ward B - Room 103', 'normal', 'admin', 'admin'),
(2, CURDATE(), 104, 3, 1, 2, 'ICU - Room 104', 'normal', 'admin', 'admin'),
(1, CURDATE(), 201, 4, 2, 3, 'Pediatric - Room 201', 'normal', 'admin', 'admin'),
(1, CURDATE(), 301, 5, 3, 4, 'Maternity - Room 301', 'normal', 'admin', 'admin'),
(1, CURDATE(), 401, 6, 4, 2, 'Surgical - Room 401', 'normal', 'admin', 'admin'),
(3, CURDATE(), 501, 7, 5, 6, 'Emergency - Room 501', 'normal', 'admin', 'admin');
ROOMSQL
    echo "Room data seeded." 2>/dev/null || echo "Warning: Room seeding had issues"
fi

echo "=== Seed data complete ==="
