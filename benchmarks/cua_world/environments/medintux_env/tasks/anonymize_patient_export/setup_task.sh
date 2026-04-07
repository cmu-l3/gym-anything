#!/bin/bash
set -euo pipefail
echo "=== Setting up anonymize_patient_export task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Ensure MySQL is running
echo "Ensuring MySQL is available..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3
for i in $(seq 1 20); do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL ready"
        break
    fi
    sleep 2
done

# Ensure DrTuxTest database and tables exist
mysql -u root -e "CREATE DATABASE IF NOT EXISTS DrTuxTest CHARACTER SET utf8 COLLATE utf8_general_ci" 2>/dev/null || true

# Create tables if they don't exist (idempotent)
mysql -u root DrTuxTest <<'SQL_EOF'
CREATE TABLE IF NOT EXISTS IndexNomPrenom (
    FchGnrl_IDDos VARCHAR(128) NOT NULL,
    FchGnrl_NomDos VARCHAR(128) DEFAULT '',
    FchGnrl_Prenom VARCHAR(128) DEFAULT '',
    FchGnrl_Type VARCHAR(64) DEFAULT 'Dossier',
    PRIMARY KEY (FchGnrl_IDDos)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS fchpat (
    FchPat_PK INT AUTO_INCREMENT PRIMARY KEY,
    FchPat_GUID_Doss VARCHAR(128) DEFAULT '',
    FchPat_NomFille VARCHAR(128) DEFAULT '',
    FchPat_Nee VARCHAR(20) DEFAULT '',
    FchPat_Sexe VARCHAR(4) DEFAULT '',
    FchPat_Titre VARCHAR(20) DEFAULT '',
    FchPat_Adresse VARCHAR(256) DEFAULT '',
    FchPat_CP VARCHAR(10) DEFAULT '',
    FchPat_Ville VARCHAR(128) DEFAULT '',
    FchPat_Tel1 VARCHAR(30) DEFAULT '',
    FchPat_NumSS VARCHAR(30) DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
SQL_EOF

# Clear existing data to ensure clean state
mysql -u root DrTuxTest -e "TRUNCATE TABLE IndexNomPrenom; TRUNCATE TABLE fchpat;" 2>/dev/null || true

# Clean any previous task attempts
rm -rf /home/ga/research_export 2>/dev/null || true

# Seed realistic patient records (common French demographics)
# These provide a deterministic set for verification
echo "Seeding patient records..."

seed_patient() {
    local guid="$1" nom="$2" prenom="$3" nee="$4" sexe="$5" titre="$6"
    local adresse="$7" cp="$8" ville="$9" tel="${10}" numss="${11}"
    mysql -u root DrTuxTest -e \
        "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) \
         VALUES ('$guid','$nom','$prenom','Dossier')" 2>/dev/null
    mysql -u root DrTuxTest -e \
        "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS) \
         VALUES ('$guid','$nom','$nee','$sexe','$titre','$adresse','$cp','$ville','$tel','$numss')" 2>/dev/null
}

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-111111111111}" "DUPONT" "Marie" "1965-03-15" "F" "Mme" \
    "12 Rue de la Paix" "75002" "Paris" "01 45 67 89 01" "2650375002123 45"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-222222222222}" "MARTIN" "Jean-Pierre" "1948-11-22" "H" "M" \
    "45 Avenue Victor Hugo" "69003" "Lyon" "04 78 90 12 34" "1481169003456 78"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-333333333333}" "BERNARD" "Sophie" "1982-07-04" "F" "Mme" \
    "8 Boulevard Gambetta" "33000" "Bordeaux" "05 56 78 90 12" "2820733000789 01"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-444444444444}" "PETIT" "François" "1935-01-30" "H" "M" \
    "22 Rue du Faubourg Saint-Honoré" "75008" "Paris" "01 42 56 78 90" "1350175008234 56"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-555555555555}" "DUBOIS" "Catherine" "1990-09-12" "F" "Mlle" \
    "3 Impasse des Lilas" "13001" "Marseille" "04 91 23 45 67" "2900913001567 89"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-666666666666}" "MOREAU" "Philippe" "1972-05-28" "H" "Dr" \
    "17 Rue de la République" "31000" "Toulouse" "05 61 23 45 67" "1720531000890 12"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-777777777777}" "LAURENT" "Isabelle" "1958-12-03" "F" "Mme" \
    "56 Allée des Platanes" "44000" "Nantes" "02 40 12 34 56" "2581244000345 67"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-888888888888}" "LEROY" "Michel" "1944-04-18" "H" "M" \
    "9 Place de la Cathédrale" "67000" "Strasbourg" "03 88 12 34 56" "1440467000678 90"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-999999999999}" "ROUX" "Chantal" "1977-08-21" "F" "Mme" \
    "31 Chemin du Moulin" "06000" "Nice" "04 93 12 34 56" "2770806000901 23"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-AAAAAAAAAAAA}" "FOURNIER" "Antoine" "2001-02-14" "H" "M" \
    "2 Rue Pasteur" "35000" "Rennes" "02 99 12 34 56" "1010235000234 56"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-BBBBBBBBBBBB}" "GIRARD" "Élise" "1988-06-07" "F" "Mme" \
    "14 Rue Jean Jaurès" "59000" "Lille" "03 20 12 34 56" "2880659000567 89"

seed_patient "{A1B2C3D4-E5F6-7890-ABCD-CCCCCCCCCCCC}" "BONNET" "Yves" "1955-10-25" "H" "M" \
    "7 Route de Genève" "01000" "Bourg-en-Bresse" "04 74 12 34 56" "1551001000890 12"

# Record patient count for verification
PATIENT_COUNT=12
echo "$PATIENT_COUNT" > /tmp/expected_patient_count.txt
echo "Total patient records: $PATIENT_COUNT"

# Dump PII values for verification cross-reference (hidden from agent)
# These will be used by the host-side verifier to detect leaks
VERIFY_DIR="/tmp/task_verification"
rm -rf "$VERIFY_DIR"
mkdir -p "$VERIFY_DIR"

mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_NomDos FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null \
    > "$VERIFY_DIR/original_names.txt"
mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_Prenom FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null \
    > "$VERIFY_DIR/original_prenoms.txt"
mysql -u root DrTuxTest -N -e \
    "SELECT FchPat_NumSS FROM fchpat WHERE FchPat_NumSS != ''" 2>/dev/null \
    > "$VERIFY_DIR/original_ssn.txt"
mysql -u root DrTuxTest -N -e \
    "SELECT FchPat_Adresse FROM fchpat WHERE FchPat_Adresse != ''" 2>/dev/null \
    > "$VERIFY_DIR/original_addresses.txt"
mysql -u root DrTuxTest -N -e \
    "SELECT FchPat_Tel1 FROM fchpat WHERE FchPat_Tel1 != ''" 2>/dev/null \
    > "$VERIFY_DIR/original_phones.txt"
mysql -u root DrTuxTest -N -e \
    "SELECT FchGnrl_IDDos FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null \
    > "$VERIFY_DIR/original_guids.txt"

chmod 700 "$VERIFY_DIR"

# Open a terminal for the agent to work in
su - ga -c "DISPLAY=:1 xterm -geometry 120x40+50+50 -title 'MedinTux Task Terminal' -e bash &" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="