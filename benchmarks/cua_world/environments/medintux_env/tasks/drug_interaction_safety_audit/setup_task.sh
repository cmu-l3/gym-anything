#!/bin/bash
set -e
echo "=== Setting up Drug Interaction Safety Audit Task ==="

source /workspace/scripts/task_utils.sh

# Directory for ground truth (hidden from agent)
GT_DIR="/var/lib/medintux"
mkdir -p "$GT_DIR"
GT_FILE="$GT_DIR/ground_truth_interaction.csv"

# Directory for output
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Helper function to run MySQL queries
run_sql() {
    mysql -u root DrTuxTest -N -e "$1"
}

# 1. Clean up output file if it exists
rm -f /home/ga/Documents/interaction_alert_list.csv

# 2. Python script to inject data and generate ground truth
# This ensures we handle the MedinTux schema complexities (Rubriques/Blobs) programmatically
cat > /tmp/inject_audit_data.py << 'EOF'
import pymysql
import random
import uuid
import csv
import sys

# Connect to DB
conn = pymysql.connect(host='localhost', user='root', password='', database='DrTuxTest', autocommit=True)
cursor = conn.cursor()

def get_existing_patients():
    # Fetch GUID, Lastname, Firstname
    cursor.execute("SELECT FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'")
    return cursor.fetchall()

def create_patient(lastname, firstname):
    guid = str(uuid.uuid4()).upper()
    # Insert into IndexNomPrenom
    cursor.execute(f"INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('{guid}', '{lastname}', '{firstname}', 'Dossier')")
    # Insert into fchpat (minimal)
    cursor.execute(f"INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe) VALUES ('{guid}', '{lastname}', '1980-01-01', 'F')")
    return (guid, lastname, firstname)

# Ensure we have enough patients
patients = get_existing_patients()
needed = 20 - len(patients)
if needed > 0:
    print(f"Creating {needed} additional patients...")
    names = [
        ("DUPONT", "Jean"), ("MARTIN", "Marie"), ("DURAND", "Pierre"), ("LEROY", "Sophie"),
        ("MOREAU", "Luc"), ("SIMON", "Julie"), ("LAURENT", "Thomas"), ("LEFEBVRE", "Claire"),
        ("MICHEL", "Nicolas"), ("GARCIA", "Ana"), ("DAVID", "David"), ("BERTRAND", "Celine"),
        ("ROUX", "Paul"), ("VINCENT", "Isabelle"), ("FOURNIER", "Marc"), ("MOREL", "Emilie"),
        ("GIRARD", "Philippe"), ("ANDRE", "Sandrine"), ("LEFEVRE", "Julien"), ("MERCIER", "Audrey")
    ]
    for i in range(needed):
        n = names[i % len(names)]
        patients.append(create_patient(f"{n[0]}_{i}", n[1]))

# Shuffle patients
random.shuffle(patients)

# Allocation
# Group A: Both (Target) - 4 patients
# Group B: Kardegic only - 5 patients
# Group C: Sintrom only - 5 patients
# Group D: Neither - Rest
group_both = patients[0:4]
group_kard = patients[4:9]
group_sint = patients[9:14]
group_none = patients[14:]

targets = []

# Templates for clinical notes
templates_kardegic = [
    "Traitement par Kardégic 75mg poursuivi.",
    "Prescription: Kardégic 160mg 1 sachet par jour.",
    "Antécédents: Infarctus traité par KARDEGIC.",
    "Allergie au Kardégic signalée par le patient."
]
templates_sintrom = [
    "Sous Sintrom avec INR cible 2-3.",
    "Arrêt temporaire du Sintrom pour chirurgie.",
    "Relais héparine/Sintrom débuté ce jour.",
    "SINTROM 4mg: 1/2 comprimé le soir."
]
templates_neutral = [
    "Consultation de routine. RAS.",
    "Douleurs abdominales diffuses.",
    "Vaccination grippe effectuée.",
    "Certificat de non contre-indication au sport."
]

def inject_note(guid, text):
    # Determine table structure
    # Check if RubriquesBlobs exists
    try:
        cursor.execute("SHOW TABLES LIKE 'RubriquesBlobs'")
        has_blobs = cursor.fetchone()
        
        # Determine columns for Rubriques
        cursor.execute("SHOW COLUMNS FROM Rubriques")
        cols = [c[0] for c in cursor.fetchall()]
        
        rub_guid = str(uuid.uuid4()).upper()
        # RbDate_PrimKey is usually auto-inc, but let's check. Assuming auto-inc or handled by DB.
        # We need to insert a record. 
        # Common structure: RbDate_IDDos (Patient GUID), RbDate_TypeRub (Type), RbDate_NomRub (Name), RbDate_Date
        
        # NOTE: MedinTux schema varies. We try a generic insert for Rubriques.
        # If RubriquesBlobs exists, text goes there, linked by RbDate_RefBlobs or similar.
        
        if has_blobs and 'RbDate_RefBlobs' in cols:
             # Insert Blob first
             cursor.execute("INSERT INTO RubriquesBlobs (RbBlobs_Blob) VALUES (%s)", (text,))
             blob_id = cursor.lastrowid
             
             # Insert Header
             # Try standard columns
             sql = "INSERT INTO Rubriques (RbDate_IDDos, RbDate_TypeRub, RbDate_NomRub, RbDate_Date, RbDate_RefBlobs) VALUES (%s, %s, %s, NOW(), %s)"
             cursor.execute(sql, (guid, 'OBS', 'Observation', blob_id))
        else:
             # Try inserting text directly into Rubriques if there's a text column like RbDate_Texte
             # If not, we might be in a version where text is elsewhere, but let's try RbDate_Texte or similar
             text_col = next((c for c in cols if 'Texte' in c or 'Blob' in c), None)
             if text_col:
                 sql = f"INSERT INTO Rubriques (RbDate_IDDos, RbDate_TypeRub, RbDate_NomRub, RbDate_Date, {text_col}) VALUES (%s, %s, %s, NOW(), %s)"
                 cursor.execute(sql, (guid, 'OBS', 'Observation', text))
             else:
                 # Fallback: Create a simpler 'Notes' table if we can't figure it out, 
                 # but the task requires finding it.
                 # Let's hope DrTuxTest has standard structure.
                 # Force creation of a simpler table for the sake of the task if needed?
                 # No, better to use what's there.
                 # Assuming RubriquesBlobs strategy worked or we failed.
                 pass
                 
    except Exception as e:
        print(f"Error injecting note: {e}")

# Inject data
for p in group_both:
    t1 = random.choice(templates_kardegic)
    t2 = random.choice(templates_sintrom)
    inject_note(p[0], f"{t1}\n{t2}")
    targets.append(p)

for p in group_kard:
    inject_note(p[0], random.choice(templates_kardegic))

for p in group_sint:
    inject_note(p[0], random.choice(templates_sintrom))

for p in group_none:
    inject_note(p[0], random.choice(templates_neutral))

# Write ground truth
with open(sys.argv[1], 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['PatientName', 'GUID'])
    for p in targets:
        name = f"{p[1]} {p[2]}"
        writer.writerow([name, p[0]])
        
print(f"Ground truth generated with {len(targets)} targets.")
EOF

# Run the python script
python3 /tmp/inject_audit_data.py "$GT_FILE"

# Clean up
rm /tmp/inject_audit_data.py

echo "Ground truth created at $GT_FILE"

# Launch MedinTux Manager (optional, but good practice to have app running)
launch_medintux_manager > /dev/null 2>&1 &

echo "=== Task setup complete ==="