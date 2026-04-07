#!/bin/bash
set -e
echo "=== Setting up restore_patient_from_backup task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if ! pgrep -x "mysqld" > /dev/null; then
    echo "Starting MySQL..."
    service mysql start
    sleep 5
fi

# ============================================================
# 1. PREPARE THE DATA
# ============================================================

# Define patient details
PATIENT_NOM="SOUBIROUS"
PATIENT_PRENOM="Bernadette"
PATIENT_DOB="1954-02-18"
PATIENT_GUID="23049F78-9A21-4B3C-8D5E-123456789ABC" # Fixed GUID for consistency
PATIENT_ADDRESS="14 Grotte de Massabielle"
PATIENT_CITY="Lourdes"
PATIENT_CP="65100"
PATIENT_TEL="05.62.42.78.78"
PATIENT_SSN="2540265100123"

echo "Creating patient $PATIENT_NOM $PATIENT_PRENOM (GUID: $PATIENT_GUID)..."

# Clean up if exists
delete_patient "$PATIENT_NOM" "$PATIENT_PRENOM"

# Insert into IndexNomPrenom (Search Index)
mysql -u root DrTuxTest -e \
    "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
     VALUES ('$PATIENT_GUID', '$PATIENT_NOM', '$PATIENT_PRENOM', 'Dossier')"

# Insert into fchpat (Patient Details)
mysql -u root DrTuxTest -e \
    "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
     FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
     VALUES ('$PATIENT_GUID', '$PATIENT_NOM', '$PATIENT_DOB', 'F', 'Mme', \
     '$PATIENT_ADDRESS', '$PATIENT_CP', '$PATIENT_CITY', '$PATIENT_TEL', '$PATIENT_SSN')"

# Verify insertion
COUNT=$(patient_exists "$PATIENT_NOM" "$PATIENT_PRENOM")
if [ "$COUNT" -eq 0 ]; then
    echo "ERROR: Failed to insert setup patient."
    exit 1
fi

# Save Ground Truth GUID for verification (hidden from agent)
mkdir -p /var/lib/medintux_task
echo "$PATIENT_GUID" > /var/lib/medintux_task/ground_truth_guid.txt
chmod 600 /var/lib/medintux_task/ground_truth_guid.txt

# ============================================================
# 2. CREATE BACKUP
# ============================================================

echo "Creating database backup..."
mkdir -p /home/ga/Documents
# Use --skip-extended-insert so each row is a separate INSERT statement (easier to grep)
mysqldump -u root --skip-extended-insert DrTuxTest > /home/ga/Documents/medintux_backup.sql

echo "Backup created at /home/ga/Documents/medintux_backup.sql"
chown ga:ga /home/ga/Documents/medintux_backup.sql

# ============================================================
# 3. DESTROY THE DATA (The Problem State)
# ============================================================

echo "Simulating accidental deletion..."
delete_patient "$PATIENT_NOM" "$PATIENT_PRENOM"

# Verify deletion
COUNT_AFTER=$(patient_exists "$PATIENT_NOM" "$PATIENT_PRENOM")
if [ "$COUNT_AFTER" -ne 0 ]; then
    echo "ERROR: Failed to delete patient for task setup."
    exit 1
fi

echo "Patient deleted. System ready for restoration task."

# ============================================================
# 4. LAUNCH APPLICATION
# ============================================================

# Launch MedinTux Manager so the agent can inspect the DB visually if they want
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="