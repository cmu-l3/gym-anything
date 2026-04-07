#!/bin/bash
set -e
echo "=== Setting up Detect Phonetic Duplicates Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Install python dependencies if needed (pymysql is usually pre-installed in env)
pip3 install pymysql --break-system-packages 2>/dev/null || pip3 install pymysql 2>/dev/null || true

# Prepare Ground Truth Data Injection
# We will inject specific cases to test the agent's fuzzy matching logic
echo "Injecting test data..."

python3 -c "
import pymysql
import uuid
import json
import os

def get_guid():
    return str(uuid.uuid4()).upper()

try:
    conn = pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest', autocommit=True)
    cursor = conn.cursor()
    
    # Helper to insert patient
    def insert_patient(last, first, dob, sex='M'):
        guid = get_guid()
        # Insert into IndexNomPrenom (Search Index)
        cursor.execute(
            'INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES (%s, %s, %s, %s)',
            (guid, last, first, 'Dossier')
        )
        # Insert into fchpat (Demographics)
        cursor.execute(
            'INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe) VALUES (%s, %s, %s, %s)',
            (guid, last, dob, sex)
        )
        return guid

    # 1. Exact Duplicate (Baseline)
    # MARTIN Alice, 1980-01-01
    g1 = insert_patient('MARTIN', 'Alice', '1980-01-01', 'F')
    g2 = insert_patient('MARTIN', 'Alice', '1980-01-01', 'F')
    
    # 2. Accent Difference (Fuzzy)
    # Hélène DUBOIS vs Helene DUBOIS, 1985-05-15
    g3 = insert_patient('DUBOIS', 'Hélène', '1985-05-15', 'F')
    g4 = insert_patient('DUBOIS', 'Helene', '1985-05-15', 'F')

    # 3. Typo/Phonetic Difference (Fuzzy)
    # PHILIPPE LEGRAND vs PHILLIPE LEGRAND, 1970-10-20
    g5 = insert_patient('LEGRAND', 'PHILIPPE', '1970-10-20', 'M')
    g6 = insert_patient('LEGRAND', 'PHILLIPE', '1970-10-20', 'M')
    
    # 4. Homonym Control (Should NOT be flagged)
    # Thomas BERNARD 1990-01-01 vs Thomas BERNARD 1992-01-01
    g7 = insert_patient('BERNARD', 'Thomas', '1990-01-01', 'M')
    g8 = insert_patient('BERNARD', 'Thomas', '1992-01-01', 'M')

    # Save Ground Truth for Verifier (Hidden)
    ground_truth = {
        'exact_match': {'names': ['MARTIN Alice'], 'dob': '1980-01-01'},
        'accent_match': {'names': ['DUBOIS Hélène', 'DUBOIS Helene'], 'dob': '1985-05-15'},
        'typo_match': {'names': ['LEGRAND PHILIPPE', 'LEGRAND PHILLIPE'], 'dob': '1970-10-20'},
        'homonym_control': {'name': 'BERNARD Thomas', 'dobs': ['1990-01-01', '1992-01-01']}
    }
    
    os.makedirs('/var/lib/medintux', exist_ok=True)
    with open('/var/lib/medintux/ground_truth.json', 'w') as f:
        json.dump(ground_truth, f)
        
    print('Injection complete.')

except Exception as e:
    print(f'Error injecting data: {e}')
    exit(1)
"

# Clean up any previous run artifacts
rm -f /home/ga/Documents/duplicate_candidates.json
rm -f /home/ga/Documents/detect_duplicates.py

# Ensure directory exists
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="