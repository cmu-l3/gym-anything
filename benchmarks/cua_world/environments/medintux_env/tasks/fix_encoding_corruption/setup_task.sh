#!/bin/bash
set -e
echo "=== Setting up fix_encoding_corruption task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
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

echo "Preparing corrupted data..."

# Clean up any previous attempts for these specific patients to ensure known state
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_NomFille IN ('BERENGER', 'LEFEVRE', 'GONÃ§ALVES', 'GONÇALVES', 'PREVOST', 'FORTIER', 'BEAUPRÃ©', 'BEAUPRÉ');" 2>/dev/null || true
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos IN ('BERENGER', 'LEFEVRE', 'GONÃ§ALVES', 'GONÇALVES', 'PREVOST', 'FORTIER', 'BEAUPRÃ©', 'BEAUPRÉ');" 2>/dev/null || true

# Helper function to insert corrupted patient
insert_corrupt() {
    local nom="$1"
    local prenom="$2"
    local adresse="$3"
    local ville="$4"
    local guid="$(cat /proc/sys/kernel/random/uuid | tr '[:lower:]' '[:upper:]')"
    
    # Insert into search index
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$guid', '$nom', '$prenom', 'Dossier')"
    
    # Insert into patient details
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1) \
         VALUES ('$guid', '$nom', '1980-01-01', 'F', 'Mme', '$adresse', '75000', '$ville', '0102030405')"
}

# Insert the 6 corrupted records
# Note: We use literal corrupted strings here.
# 1. BERENGER Léa -> LÃ©a, Châteauroux -> ChÃ¢teauroux
insert_corrupt "BERENGER" "LÃ©a" "10 rue de la Paix" "ChÃ¢teauroux"

# 2. LEFEVRE Hélène -> HÃ©lÃ¨ne, 14 rue des Pêcheurs -> 14 rue des PÃªcheurs
insert_corrupt "LEFEVRE" "HÃ©lÃ¨ne" "14 rue des PÃªcheurs" "Paris"

# 3. GONÇALVES -> GONÃ§ALVES (Nom corrupted)
insert_corrupt "GONÃ§ALVES" "Maria" "12 Av du Portugal" "Paris"

# 4. PREVOST Renée -> RenÃ©e
insert_corrupt "PREVOST" "RenÃ©e" "5 Bd Haussmann" "Paris"

# 5. FORTIER Françoise -> FranÃ§oise, Orléans -> OrlÃ©ans
insert_corrupt "FORTIER" "FranÃ§oise" "8 Impasse du Sud" "OrlÃ©ans"

# 6. BEAUPRÉ -> BEAUPRÃ©, Thérèse -> ThÃ©rÃ¨se, 3 rue François Rabelais -> 3 rue FranÃ§ois Rabelais
insert_corrupt "BEAUPRÃ©" "ThÃ©rÃ¨se" "3 rue FranÃ§ois Rabelais" "Tours"

# Record initial total count to verify no accidental deletions later
INITIAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'")
echo "$INITIAL_COUNT" > /tmp/initial_patient_count.txt

# Launch MedinTux Manager (so the agent has the tool open, even if they use CLI)
launch_medintux_manager

# Ensure document directory exists for the report
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="