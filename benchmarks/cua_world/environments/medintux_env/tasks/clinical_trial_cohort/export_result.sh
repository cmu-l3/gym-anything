#!/bin/bash
echo "=== Exporting Clinical Trial Cohort Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

CSV_PATH="/home/ga/Documents/cohort_dm2_oral_2024.csv"
SUMMARY_PATH="/home/ga/Documents/cohort_summary_dm2_oral_2024.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run a Python script inside the container to analyze the results against the DB ground truth
# This avoids complicated bash parsing of CSVs
python3 -c "
import csv
import json
import os
import sys
import datetime
import pymysql

# Config
task_start = $TASK_START
csv_path = '$CSV_PATH'
summary_path = '$SUMMARY_PATH'
db_user = 'root'
db_password = ''
db_name = 'DrTuxTest'

result = {
    'task_start': task_start,
    'csv_exists': False,
    'csv_valid_format': False,
    'summary_exists': False,
    'summary_content_ok': False,
    'row_count_match': False,
    'age_accuracy': 0.0,
    'eligibility_accuracy': 0.0,
    'exclusion_reason_ok': False,
    'db_table_list_present': False,
    'cim10_codes_present': False,
    'errors': []
}

def calculate_age(dob_str):
    try:
        if not dob_str or dob_str == 'NULL': return None
        dob = datetime.datetime.strptime(dob_str, '%Y-%m-%d').date()
        today = datetime.date.today()
        return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))
    except:
        return None

try:
    # 1. Check Files Existence and Timestamps
    if os.path.exists(csv_path):
        result['csv_exists'] = True
        mtime = os.path.getmtime(csv_path)
        if mtime < task_start:
            result['errors'].append('CSV file pre-dates task start')
    
    if os.path.exists(summary_path):
        result['summary_exists'] = True
        mtime = os.path.getmtime(summary_path)
        if mtime < task_start:
            result['errors'].append('Summary file pre-dates task start')

    # 2. Get Ground Truth from DB
    conn = pymysql.connect(host='localhost', user=db_user, password=db_password, database=db_name)
    cursor = conn.cursor(pymysql.cursors.DictCursor)
    
    # Get patients
    query = '''
        SELECT 
            i.FchGnrl_IDDos as guid, 
            i.FchGnrl_NomDos as nom, 
            i.FchGnrl_Prenom as prenom, 
            f.FchPat_Nee as dob
        FROM IndexNomPrenom i 
        JOIN fchpat f ON i.FchGnrl_IDDos = f.FchPat_GUID_Doss
        WHERE i.FchGnrl_Type='Dossier'
    '''
    cursor.execute(query)
    db_patients = {row['guid']: row for row in cursor.fetchall()}
    
    # Process Ground Truth Logic
    gt_stats = {'total': 0, 'eligible': 0, 'excluded': 0}
    for guid, p in db_patients.items():
        gt_stats['total'] += 1
        age = calculate_age(str(p['dob']))
        p['age'] = age
        
        # Eligibility Logic
        # Criteria: Age 30-75, Name present, DOB present
        eligible = False
        reason = []
        
        if not p['nom']: reason.append('missing_name')
        if not p['dob']: reason.append('missing_dob')
        
        if age is not None:
            if age < 30: reason.append('age_under_30')
            if age > 75: reason.append('age_over_75')
        else:
            reason.append('invalid_dob')
            
        if not reason:
            eligible = True
            p['status'] = 'ELIGIBLE'
        else:
            p['status'] = 'EXCLUDED'
            
        if eligible: gt_stats['eligible'] += 1
        else: gt_stats['excluded'] += 1

    # 3. Analyze Agent CSV
    if result['csv_exists']:
        try:
            with open(csv_path, 'r', encoding='utf-8', errors='replace') as f:
                reader = csv.DictReader(f)
                
                # Check columns
                required = ['patient_guid', 'nom', 'prenom', 'date_naissance', 'age', 'sexe', 'eligibility', 'exclusion_reason']
                if reader.fieldnames and all(c in reader.fieldnames for c in required):
                    result['csv_valid_format'] = True
                else:
                    result['errors'].append(f'Missing columns. Found: {reader.fieldnames}')
                
                rows = list(reader)
                
                # Check Row Count
                # Allow small deviation if DB changed, but usually should match exact
                if abs(len(rows) - len(db_patients)) <= 1:
                    result['row_count_match'] = True
                else:
                    result['errors'].append(f'Row count mismatch: CSV={len(rows)}, DB={len(db_patients)}')

                # Verify content accuracy
                correct_age_count = 0
                correct_status_count = 0
                correct_reason_logic = 0
                checked_count = 0
                
                for row in rows:
                    guid = row.get('patient_guid')
                    if guid in db_patients:
                        checked_count += 1
                        gt = db_patients[guid]
                        
                        # Check Age (allow +/- 1 year diff for timezone/calc diffs)
                        try:
                            csv_age = int(float(row.get('age', -99)))
                            if gt['age'] is not None and abs(csv_age - gt['age']) <= 1:
                                correct_age_count += 1
                        except:
                            pass
                        
                        # Check Status
                        csv_status = row.get('eligibility', '').upper()
                        if csv_status == gt['status']:
                            correct_status_count += 1
                            
                        # Check Reason consistency
                        reason = row.get('exclusion_reason', '').strip()
                        if csv_status == 'ELIGIBLE' and not reason:
                            correct_reason_logic += 1
                        elif csv_status == 'EXCLUDED' and reason:
                            correct_reason_logic += 1
                            
                if checked_count > 0:
                    result['age_accuracy'] = correct_age_count / checked_count
                    result['eligibility_accuracy'] = correct_status_count / checked_count
                    if correct_reason_logic / checked_count > 0.9:
                        result['exclusion_reason_ok'] = True
        except Exception as e:
            result['errors'].append(f'CSV parsing error: {str(e)}')

    # 4. Analyze Summary Report
    if result['summary_exists']:
        try:
            with open(summary_path, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                
            # Check for key content
            checks = 0
            if 'DM2-ORAL-2024' in content: checks += 1
            if str(gt_stats['total']) in content or str(len(db_patients)) in content: checks += 1
            
            # Check for Table List (DrTuxTest tables)
            # Just check for a few known tables to confirm they listed them
            if 'fchpat' in content and 'IndexNomPrenom' in content:
                result['db_table_list_present'] = True
                checks += 1
                
            # Check for CIM10 codes
            # E11 is Type 2 Diabetes
            if 'E11' in content:
                result['cim10_codes_present'] = True
                checks += 1
                
            if checks >= 3:
                result['summary_content_ok'] = True
                
        except Exception as e:
            result['errors'].append(f'Summary parsing error: {str(e)}')

    conn.close()
    
except Exception as e:
    result['errors'].append(f'Script error: {str(e)}')

print(json.dumps(result))
" > /tmp/analysis_result.json

# Copy result to the final location
mv /tmp/analysis_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Analysis complete. Result saved."