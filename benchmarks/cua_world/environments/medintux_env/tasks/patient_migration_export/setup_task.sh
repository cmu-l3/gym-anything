#!/bin/bash
set -e
echo "=== Setting up Patient Migration Export Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# Clean up any previous run artifacts
mysql -u root DrTuxTest -e "DROP TABLE IF EXISTS patient_export;" 2>/dev/null || true
rm -f /home/ga/Documents/patient_export.csv
rm -f /home/ga/Documents/migration_summary.txt

# ==============================================================================
# GENERATE REALISTIC DATASET
# ==============================================================================
# We use Python to generate SQL to ensure complex, realistic data
# and calculate ground truth statistics simultaneously.
# ==============================================================================

cat > /tmp/generate_data.py << 'EOF'
import uuid
import random
import json
import sys

# Constants for data generation
SURNAMES = ["MARTIN", "BERNARD", "THOMAS", "PETIT", "ROBERT", "RICHARD", "DURAND", "DUBOIS", "MOREAU", "LAURENT", "SIMON", "MICHEL", "LEFEBVRE", "LEROY", "ROUX", "DAVID", "BERTRAND", "MOREL", "FOURNIER", "GIRARD"]
MALE_NAMES = ["Jean", "Pierre", "Michel", "Philippe", "Alain", "Patrick", "Nicolas", "Christophe", "Pascal", "Christian", "Eric", "Frédéric", "Laurent", "Olivier", "Stéphane", "David", "Sébastien", "Julien", "Thierry", "Bruno"]
FEMALE_NAMES = ["Marie", "Nathalie", "Isabelle", "Sylvie", "Catherine", "Martine", "Christine", "Monique", "Valérie", "Sandrine", "Véronique", "Nicole", "Stéphanie", "Sophie", "Céline", "Chantal", "Patricia", "Anne", "Brigitte", "Julie"]
CITIES = [("75001", "Paris"), ("69002", "Lyon"), ("13003", "Marseille"), ("33000", "Bordeaux"), ("59000", "Lille"), ("31000", "Toulouse"), ("44000", "Nantes"), ("67000", "Strasbourg")]
STREETS = ["Rue de la Paix", "Avenue Victor Hugo", "Boulevard Haussmann", "Rue de Rivoli", "Champs-Élysées", "Rue du Commerce", "Avenue des Ternes", "Rue Cler"]

patients = []
stats = {
    "total": 0,
    "male": 0,
    "female": 0,
    "missing_phone": 0,
    "missing_address": 0
}

# Generate 20-25 patients
num_patients = random.randint(20, 25)

print(f"Generating {num_patients} patients...")

sql_statements = []

for i in range(num_patients):
    guid = str(uuid.uuid4()).upper()
    
    is_female = random.choice([True, False])
    sex = "F" if is_female else "M"
    
    last_name = random.choice(SURNAMES)
    first_name = random.choice(FEMALE_NAMES if is_female else MALE_NAMES)
    
    # Date of birth (approx 1940-2005)
    year = random.randint(1940, 2005)
    month = random.randint(1, 12)
    day = random.randint(1, 28)
    dob = f"{year}-{month:02d}-{day:02d}"
    
    # Address (sometimes empty to test migration logic)
    if random.random() < 0.15: # 15% missing address
        address = ""
        cp = "0"
        city = ""
        stats["missing_address"] += 1
    else:
        addr_pair = random.choice(CITIES)
        address = f"{random.randint(1, 150)} {random.choice(STREETS)}"
        cp = addr_pair[0]
        city = addr_pair[1]
    
    # Phone (sometimes empty)
    if random.random() < 0.20: # 20% missing phone
        phone = ""
        stats["missing_phone"] += 1
    else:
        phone = f"0{random.randint(1, 9)}.{random.randint(10, 99)}.{random.randint(10, 99)}.{random.randint(10, 99)}.{random.randint(10, 99)}"
        
    # NIR / Social Security (rough format)
    nir = f"{'2' if is_female else '1'}{str(year)[2:]}{month:02d}{cp[:2]}..."
    
    titre = "Mme" if is_female else "M."
    nom_fille = last_name if is_female and random.random() > 0.5 else ""

    # Stats
    stats["total"] += 1
    if is_female:
        stats["female"] += 1
    else:
        stats["male"] += 1
        
    # SQL generation
    # Table IndexNomPrenom
    sql_statements.append(f"INSERT IGNORE INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('{guid}', '{last_name}', '{first_name}', 'Dossier');")
    
    # Table fchpat
    # Note: Address/CP/Ville handled carefully for SQL syntax
    sql_statements.append(f"INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) VALUES ('{guid}', '{nom_fille}', '{dob}', '{sex}', '{titre}', '{address}', '{cp}', '{city}', '{phone}', '{nir}');")

# Output SQL to file
with open('/tmp/insert_data.sql', 'w') as f:
    f.write("DELETE FROM fchpat;\n")
    f.write("DELETE FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier';\n")
    for stmt in sql_statements:
        f.write(stmt + "\n")

# Output Ground Truth stats to file (for verifier)
with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(stats, f)

print("Data generation complete.")
EOF

# Run the python generator
python3 /tmp/generate_data.py

# Execute the SQL to populate DB
mysql -u root DrTuxTest < /tmp/insert_data.sql

# Launch MedinTux Manager to provide GUI context
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="