#!/usr/bin/env python3
"""
Synthea to OpenEMR Data Converter

Converts Synthea synthetic patient data (CSV) to OpenEMR SQL format.
This creates realistic patient data with medical histories.

Usage:
    python synthea_to_openemr.py --synthea-dir /path/to/synthea/csv --output sample_patients.sql --count 50
"""

import csv
import argparse
import random
from datetime import datetime
from pathlib import Path

import re

def escape_sql(value):
    """Escape single quotes for SQL"""
    if value is None:
        return ''
    return str(value).replace("'", "''").replace("\\", "\\\\")

def clean_synthea_name(name):
    """Remove numeric suffixes from Synthea names (e.g., 'Jacinto644' -> 'Jacinto')"""
    if not name:
        return ''
    # Remove trailing digits
    return re.sub(r'\d+$', '', name)

def convert_gender(synthea_gender):
    """Convert Synthea gender to OpenEMR format"""
    if synthea_gender == 'M':
        return 'Male'
    elif synthea_gender == 'F':
        return 'Female'
    return 'Other'

def convert_race(synthea_race):
    """Convert Synthea race to OpenEMR format"""
    race_map = {
        'white': 'white',
        'black': 'black_or_afri_amer',
        'asian': 'asian',
        'native': 'amer_ind_or_alaska_native',
        'other': 'other'
    }
    return race_map.get(synthea_race.lower(), 'decline_to_specify')

def convert_ethnicity(synthea_ethnicity):
    """Convert Synthea ethnicity to OpenEMR format"""
    if synthea_ethnicity and 'hispanic' in synthea_ethnicity.lower():
        return 'hisp_or_latin'
    return 'not_hisp_or_latin'

def convert_marital(synthea_marital):
    """Convert Synthea marital status to OpenEMR format"""
    status_map = {
        'M': 'married',
        'S': 'single',
        'D': 'divorced',
        'W': 'widowed',
        '': 'single'
    }
    return status_map.get(synthea_marital, 'single')

def load_synthea_patients(synthea_dir, count=50):
    """Load patients from Synthea CSV"""
    patients_file = Path(synthea_dir) / 'patients.csv'
    patients = []

    with open(patients_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i >= count:
                break
            # Skip deceased patients for demo
            if row.get('DEATHDATE'):
                continue
            patients.append(row)
            if len(patients) >= count:
                break

    return patients

def load_synthea_conditions(synthea_dir, patient_ids):
    """Load conditions for given patients"""
    conditions_file = Path(synthea_dir) / 'conditions.csv'
    conditions = {}

    with open(conditions_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row.get('PATIENT')
            if pid in patient_ids:
                if pid not in conditions:
                    conditions[pid] = []
                conditions[pid].append(row)

    return conditions

def load_synthea_medications(synthea_dir, patient_ids):
    """Load medications for given patients"""
    meds_file = Path(synthea_dir) / 'medications.csv'
    medications = {}

    with open(meds_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row.get('PATIENT')
            if pid in patient_ids:
                if pid not in medications:
                    medications[pid] = []
                medications[pid].append(row)

    return medications

def load_synthea_encounters(synthea_dir, patient_ids):
    """Load encounters for given patients"""
    enc_file = Path(synthea_dir) / 'encounters.csv'
    encounters = {}

    with open(enc_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row.get('PATIENT')
            if pid in patient_ids:
                if pid not in encounters:
                    encounters[pid] = []
                encounters[pid].append(row)

    return encounters

def load_synthea_allergies(synthea_dir, patient_ids):
    """Load allergies for given patients"""
    allergy_file = Path(synthea_dir) / 'allergies.csv'
    allergies = {}

    if not allergy_file.exists():
        return allergies

    with open(allergy_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row.get('PATIENT')
            if pid in patient_ids:
                if pid not in allergies:
                    allergies[pid] = []
                allergies[pid].append(row)

    return allergies

def generate_patient_sql(patients, start_pid=1):
    """Generate SQL for patient_data table (Docker OpenEMR schema compatible)"""
    sql_lines = []
    sql_lines.append("-- Synthea-generated patient data")
    sql_lines.append("-- Realistic synthetic patients with full demographics\n")

    for i, p in enumerate(patients):
        pid = start_pid + i

        # Parse address
        address = escape_sql(p.get('ADDRESS', ''))
        city = escape_sql(p.get('CITY', ''))
        state = escape_sql(p.get('STATE', ''))[:2].upper() if p.get('STATE') else 'MA'
        zipcode = escape_sql(p.get('ZIP', ''))[:5]

        # Generate phone numbers
        area_code = zipcode[:3] if len(zipcode) >= 3 else '555'
        phone_home = f"({area_code}) 555-{random.randint(1000, 9999)}"
        phone_cell = f"({area_code}) 555-{random.randint(1000, 9999)}"

        # Clean names (remove Synthea numeric suffixes)
        fname = clean_synthea_name(p.get("FIRST", ""))
        lname = clean_synthea_name(p.get("LAST", ""))

        # Docker OpenEMR uses 'id' (auto_increment) and 'pid' (primary key)
        # Also uses 'date' instead of 'create_date'
        sql = f"""INSERT INTO patient_data (
    id, pid, pubpid, fname, lname, mname, DOB, sex, ss,
    street, city, state, postal_code, country_code,
    phone_home, phone_cell, email,
    race, ethnicity, language, status,
    drivers_license, date, regdate
) VALUES (
    {pid}, {pid}, 'P{1000+pid}', '{escape_sql(fname)}', '{escape_sql(lname)}',
    '{escape_sql(p.get("SUFFIX", ""))}', '{p.get("BIRTHDATE", "1980-01-01")}',
    '{convert_gender(p.get("GENDER", ""))}', '{escape_sql(p.get("SSN", ""))}',
    '{address}', '{city}', '{state}', '{zipcode}', 'US',
    '{phone_home}', '{phone_cell}',
    '{escape_sql(fname.lower())}.{escape_sql(lname.lower())}@email.com',
    '{convert_race(p.get("RACE", ""))}', '{convert_ethnicity(p.get("ETHNICITY", ""))}',
    'English', '{convert_marital(p.get("MARITAL", ""))}',
    '{escape_sql(p.get("DRIVERS", ""))}', NOW(), NOW()
) ON DUPLICATE KEY UPDATE fname = VALUES(fname);
"""
        sql_lines.append(sql)

    return '\n'.join(sql_lines)

def generate_conditions_sql(conditions, patient_id_map):
    """Generate SQL for patient medical issues/problems"""
    sql_lines = []
    sql_lines.append("\n-- Patient medical problems/conditions")
    sql_lines.append("-- Lists (problems list)\n")

    issue_id = 1
    for synthea_id, conds in conditions.items():
        pid = patient_id_map.get(synthea_id)
        if not pid:
            continue

        # Take up to 10 conditions per patient
        for cond in conds[:10]:
            code = escape_sql(cond.get('CODE', ''))
            description = escape_sql(cond.get('DESCRIPTION', ''))
            start_date = cond.get('START', '')[:10] if cond.get('START') else ''
            end_date = cond.get('STOP', '')[:10] if cond.get('STOP') else ''

            # Determine if active or resolved (outcome is integer: 0=active, 1=resolved)
            outcome = 1 if end_date else 0

            # Handle NULL enddate properly (not as string)
            enddate_value = f"'{end_date}'" if end_date else "NULL"

            sql = f"""INSERT INTO lists (id, pid, type, title, diagnosis, begdate, enddate, outcome)
VALUES ({issue_id}, {pid}, 'medical_problem', '{description}', 'SNOMED:{code}',
    '{start_date}', {enddate_value}, {outcome})
ON DUPLICATE KEY UPDATE title = VALUES(title);
"""
            sql_lines.append(sql)
            issue_id += 1

    return '\n'.join(sql_lines)

def generate_medications_sql(medications, patient_id_map):
    """Generate SQL for prescriptions (Docker OpenEMR schema compatible)"""
    sql_lines = []
    sql_lines.append("\n-- Patient medications/prescriptions")
    sql_lines.append("-- Prescriptions table\n")

    rx_id = 1
    for synthea_id, meds in medications.items():
        pid = patient_id_map.get(synthea_id)
        if not pid:
            continue

        # Take up to 5 recent medications per patient
        for med in meds[:5]:
            drug = escape_sql(med.get('DESCRIPTION', ''))
            code = escape_sql(med.get('CODE', ''))
            start_date = med.get('START', '')[:10] if med.get('START') else ''
            end_date = med.get('STOP', '')[:10] if med.get('STOP') else ''

            # Active if no end date
            active = 1 if not end_date else 0

            # Docker OpenEMR requires txDate, usage_category_title, request_intent_title
            sql = f"""INSERT INTO prescriptions (id, patient_id, drug, rxnorm_drugcode, date_added, start_date, active, txDate, usage_category_title, request_intent_title)
VALUES ({rx_id}, {pid}, '{drug}', '{code}', '{start_date}', '{start_date}', {active}, '{start_date}', '', '')
ON DUPLICATE KEY UPDATE drug = VALUES(drug);
"""
            sql_lines.append(sql)
            rx_id += 1

    return '\n'.join(sql_lines)

def generate_allergies_sql(allergies, patient_id_map):
    """Generate SQL for patient allergies"""
    sql_lines = []
    sql_lines.append("\n-- Patient allergies")
    sql_lines.append("-- Lists (allergy type)\n")

    allergy_id = 10000  # Start high to avoid conflicts
    for synthea_id, allergens in allergies.items():
        pid = patient_id_map.get(synthea_id)
        if not pid:
            continue

        for allergy in allergens[:5]:
            description = escape_sql(allergy.get('DESCRIPTION', ''))
            code = escape_sql(allergy.get('CODE', ''))
            start_date = allergy.get('START', '')[:10] if allergy.get('START') else ''

            # outcome is integer: 0=active
            sql = f"""INSERT INTO lists (id, pid, type, title, diagnosis, begdate, outcome)
VALUES ({allergy_id}, {pid}, 'allergy', '{description}', 'SNOMED:{code}', '{start_date}', 0)
ON DUPLICATE KEY UPDATE title = VALUES(title);
"""
            sql_lines.append(sql)
            allergy_id += 1

    return '\n'.join(sql_lines)

def generate_encounters_sql(encounters, patient_id_map):
    """Generate SQL for patient encounters"""
    sql_lines = []
    sql_lines.append("\n-- Patient encounters/visits")
    sql_lines.append("-- form_encounter table\n")

    enc_id = 1
    for synthea_id, encs in encounters.items():
        pid = patient_id_map.get(synthea_id)
        if not pid:
            continue

        # Take up to 5 encounters per patient
        for enc in encs[:5]:
            enc_date = enc.get('START', '')[:10] if enc.get('START') else ''
            enc_type = escape_sql(enc.get('ENCOUNTERCLASS', 'outpatient'))
            reason = escape_sql(enc.get('REASONDESCRIPTION', 'Office Visit'))[:255]

            sql = f"""INSERT INTO form_encounter (id, pid, encounter, date, reason, facility_id, provider_id)
VALUES ({enc_id}, {pid}, {enc_id}, '{enc_date}', '{reason}', 3, 1)
ON DUPLICATE KEY UPDATE reason = VALUES(reason);
"""
            sql_lines.append(sql)
            enc_id += 1

    return '\n'.join(sql_lines)

def main():
    parser = argparse.ArgumentParser(description='Convert Synthea data to OpenEMR SQL')
    parser.add_argument('--synthea-dir', required=True, help='Path to Synthea CSV directory')
    parser.add_argument('--output', required=True, help='Output SQL file')
    parser.add_argument('--count', type=int, default=50, help='Number of patients to convert')
    args = parser.parse_args()

    print(f"Loading {args.count} patients from Synthea data...")
    patients = load_synthea_patients(args.synthea_dir, args.count)
    print(f"Loaded {len(patients)} patients")

    # Create patient ID mapping (Synthea ID -> OpenEMR pid)
    patient_ids = set()
    patient_id_map = {}
    for i, p in enumerate(patients):
        synthea_id = p.get('Id')
        patient_ids.add(synthea_id)
        patient_id_map[synthea_id] = i + 1

    print("Loading conditions...")
    conditions = load_synthea_conditions(args.synthea_dir, patient_ids)
    print(f"Loaded conditions for {len(conditions)} patients")

    print("Loading medications...")
    medications = load_synthea_medications(args.synthea_dir, patient_ids)
    print(f"Loaded medications for {len(medications)} patients")

    print("Loading allergies...")
    allergies = load_synthea_allergies(args.synthea_dir, patient_ids)
    print(f"Loaded allergies for {len(allergies)} patients")

    print("Loading encounters...")
    encounters = load_synthea_encounters(args.synthea_dir, patient_ids)
    print(f"Loaded encounters for {len(encounters)} patients")

    # Generate SQL
    print("Generating SQL...")
    sql_parts = []

    # Header
    sql_parts.append("""-- =============================================================================
-- OpenEMR Realistic Patient Data
-- Generated from Synthea Synthetic Health Data
-- https://github.com/synthetichealth/synthea
--
-- This data includes:
--   - Patient demographics with diverse backgrounds
--   - Medical conditions/problems (ICD/SNOMED coded)
--   - Medications/prescriptions (RxNorm coded)
--   - Allergies
--   - Encounter history
--
-- The data is synthetic but medically realistic, suitable for:
--   - AI agent testing
--   - EHR workflow demonstrations
--   - Training and education
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;

""")

    # Generate patient data
    sql_parts.append(generate_patient_sql(patients))

    # Generate conditions
    sql_parts.append(generate_conditions_sql(conditions, patient_id_map))

    # Generate medications
    sql_parts.append(generate_medications_sql(medications, patient_id_map))

    # Generate allergies
    sql_parts.append(generate_allergies_sql(allergies, patient_id_map))

    # Generate encounters
    sql_parts.append(generate_encounters_sql(encounters, patient_id_map))

    # Footer
    sql_parts.append("""
-- Update auto_increment for new patients
ALTER TABLE patient_data AUTO_INCREMENT = 100;

-- Create default facility if not exists
INSERT INTO facility (id, name, street, city, state, postal_code, phone, service_location, billing_location, primary_business_entity)
VALUES (3, 'Springfield Medical Center', '100 Healthcare Blvd', 'Springfield', 'MA', '01101', '555-1000', 1, 1, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name);

SET FOREIGN_KEY_CHECKS = 1;

SELECT CONCAT('Loaded ', COUNT(*), ' patients with medical histories') as status FROM patient_data WHERE pid < 100;
""")

    # Write output
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_parts))

    print(f"SQL written to {args.output}")
    print(f"Summary: {len(patients)} patients, {sum(len(c) for c in conditions.values())} conditions, {sum(len(m) for m in medications.values())} medications")

if __name__ == '__main__':
    main()
