#!/bin/bash
set -e
echo "=== Setting up Geographic Catchment Analysis Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Clean up previous runs
rm -rf /home/ga/reports
mkdir -p /home/ga/reports
chown ga:ga /home/ga/reports

# ==============================================================================
# DATA GENERATION
# We need a deterministic but diverse dataset to ensure the report is meaningful.
# We will generate ~100 patients with specific distributions.
# ==============================================================================

echo "Generating patient population data..."

# Create a Python script to generate SQL inserts
cat > /tmp/generate_patients.py << 'PYEOF'
import random
import datetime

postal_codes = [75001, 75011, 75015, 75020, 92100, 93100, 94200, 78000]
sexes = ['F', 'H']
# Age weights to ensure we have people in all brackets
# Brackets: 0-17, 18-39, 40-59, 60-79, 80+
age_ranges = [
    (0, 17, 0.15),
    (18, 39, 0.30),
    (40, 59, 0.30),
    (60, 79, 0.20),
    (80, 99, 0.05)
]

def random_date_for_age(age):
    today = datetime.date.today()
    start_year = today.year - age
    # Random day in that year
    start_date = datetime.date(start_year, 1, 1)
    end_date = datetime.date(start_year, 12, 31)
    days_between = (end_date - start_date).days
    random_days = random.randrange(days_between)
    return start_date + datetime.timedelta(days=random_days)

def generate_sql():
    print("DELETE FROM fchpat;")
    print("DELETE FROM IndexNomPrenom;")
    
    count = 0
    for _ in range(120): # Generate 120 patients
        # Pick age bracket based on weights
        r = random.random()
        cumulative = 0
        selected_range = age_ranges[-1]
        for ar in age_ranges:
            cumulative += ar[2]
            if r <= cumulative:
                selected_range = ar
                break
        
        age = random.randint(selected_range[0], selected_range[1])
        dob = random_date_for_age(age)
        
        sex = random.choice(sexes)
        cp = random.choice(postal_codes)
        
        # Generate GUID
        guid = f"TEST-PAT-{count:05d}"
        
        # Insert FchPat
        print(f"INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_CP, FchPat_Ville) VALUES ('{guid}', 'PATIENT{count}', '{dob}', '{sex}', '{cp}', 'Ville{cp}');")
        
        # Insert Index
        print(f"INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('{guid}', 'PATIENT{count}', 'Test', 'Dossier');")
        
        count += 1

generate_sql()
PYEOF

# Execute the generation script and pipe to MySQL
python3 /tmp/generate_patients.py > /tmp/populate_db.sql

echo "Populating DrTuxTest database..."
mysql -u root DrTuxTest < /tmp/populate_db.sql

# Verify count
COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat")
echo "Database populated with $COUNT patients."
echo "$COUNT" > /tmp/initial_patient_count.txt

# Launch MedinTux Manager (standard env requirement to have app running)
# We use the background launch so we don't block
launch_medintux_manager > /dev/null 2>&1 &

# Initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="