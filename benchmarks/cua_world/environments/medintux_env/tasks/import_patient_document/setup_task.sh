#!/bin/bash
set -e
echo "=== Setting up import_patient_document task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Prepare Environment & Database
# ============================================================

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# Check/Create Patient "Jean DUPONT"
# We need a known GUID to verify against later
echo "Checking for patient Jean DUPONT..."

# Get GUID if exists
GUID=$(mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_NomDos='DUPONT' AND FchGnrl_Prenom='Jean' LIMIT 1" \
    2>/dev/null || echo "")

if [ -z "$GUID" ]; then
    echo "Creating patient Jean DUPONT..."
    # Generate a pseudo-random GUID
    GUID=$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')
    
    # Insert into IndexNomPrenom (Search Index)
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$GUID', 'DUPONT', 'Jean', 'Dossier')"
         
    # Insert into fchpat (Details)
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, \
         FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$GUID', 'DUPONT', '1980-05-15', 'M', 'M.', '10 Rue des Lilas', 75012, 'Paris', \
         '06.01.02.03.04', '1800575012001')"
else
    echo "Patient exists with GUID: $GUID"
    # Clean up ANY existing documents for this patient to ensure clean verification
    # We delete from RubriquesHead and RubriquesBlob linked to this GUID
    echo "Cleaning existing documents for this patient..."
    mysql -u root DrTuxTest -e "DELETE FROM RubriquesHead WHERE RbDate_IDDos='$GUID'" 2>/dev/null || true
    # Note: RubriquesBlob cleans up usually via cascade or we leave orphaned blobs (harmless for verification)
fi

# Save GUID for export script
echo "$GUID" > /tmp/patient_guid.txt

# ============================================================
# 2. Prepare the Source Document
# ============================================================
echo "Creating dummy PDF document..."
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Create a simple PDF using ImageMagick (convert) or text
PDF_PATH="/home/ga/Desktop/cr_cardio.pdf"

# Create a text file first
echo "Compte Rendu de Consultation Cardiologique" > /tmp/cr.txt
echo "Patient: Jean DUPONT" >> /tmp/cr.txt
echo "Date: $(date +%Y-%m-%d)" >> /tmp/cr.txt
echo "Resultat: ECG Normal." >> /tmp/cr.txt

# Convert to PDF (requires imagemagick/ghostscript)
# Fallback to simple text file renamed as pdf if convert fails (MedinTux might complain, but for file picker it's fine)
if command -v convert >/dev/null 2>&1; then
    convert /tmp/cr.txt "$PDF_PATH" 2>/dev/null || cp /tmp/cr.txt "$PDF_PATH"
else
    cp /tmp/cr.txt "$PDF_PATH"
fi

# Ensure ga owns it
chown ga:ga "$PDF_PATH"
chmod 644 "$PDF_PATH"

# ============================================================
# 3. Launch Application
# ============================================================
# Kill any existing instances
pkill -f "Manager.exe" 2>/dev/null || true
sleep 2

# Launch MedinTux
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="