#!/bin/bash
set -e
echo "=== Setting up fix_inverted_names task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

echo "Preparing database with erroneous records..."

# Define the target records with fixed GUIDs for verification
# GUIDs must be unique. We use custom ones to easily track them.
GUID1="FIX-INV-001"
GUID2="FIX-INV-002"
GUID3="FIX-INV-003"

# Function to clean up any existing variations of these patients
cleanup_patient() {
    local nom="$1"
    local prenom="$2"
    local guid="$3"
    
    # Delete by GUID
    mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'" 2>/dev/null || true
    
    # Delete by Name (both correct and inverted versions)
    mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE (FchGnrl_NomDos='$nom' AND FchGnrl_Prenom='$prenom') OR (FchGnrl_NomDos='$prenom' AND FchGnrl_Prenom='$nom')" 2>/dev/null || true
    
    # We can't easily delete by name from fchpat without join, but GUID deletion covers the linked ones
}

# Clean up
cleanup_patient "MARTIN" "Sophie" "$GUID1"
cleanup_patient "PETIT" "Thomas" "$GUID2"
cleanup_patient "DUBOIS" "Lucas" "$GUID3"

# Insert Erroneous Records (Inverted Names)
# Record 1: Nom="Sophie", Prenom="MARTIN"
echo "Inserting inverted record 1: Sophie MARTIN (should be MARTIN Sophie)"
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID1', 'Sophie', 'MARTIN', 'Dossier')"
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) VALUES ('$GUID1', 'Sophie', '1980-01-01', 'F', 'Mme', '10 Rue des Fleurs', 75001, 'Paris', '0102030405', '2800175001001')"

# Record 2: Nom="Thomas", Prenom="PETIT"
echo "Inserting inverted record 2: Thomas PETIT (should be PETIT Thomas)"
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID2', 'Thomas', 'PETIT', 'Dossier')"
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) VALUES ('$GUID2', 'Thomas', '1985-05-05', 'M', 'M.', '20 Avenue Jean Jaures', 69002, 'Lyon', '0478000000', '1850569002002')"

# Record 3: Nom="Lucas", Prenom="DUBOIS"
echo "Inserting inverted record 3: Lucas DUBOIS (should be DUBOIS Lucas)"
mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID3', 'Lucas', 'DUBOIS', 'Dossier')"
mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) VALUES ('$GUID3', 'Lucas', '1990-12-12', 'M', 'M.', '5 Boulevard de la Liberté', 13001, 'Marseille', '0491000000', '1901213001003')"

# Save initial GUIDs to file for later verification (though they are hardcoded in script, this is good practice)
cat > /tmp/target_guids.json << EOF
{
  "record1": "$GUID1",
  "record2": "$GUID2",
  "record3": "$GUID3"
}
EOF

# Ensure MedinTux Manager is running (optional for this task, but good context)
if ! pgrep -f "Manager.exe" > /dev/null; then
    launch_medintux_manager
fi

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="