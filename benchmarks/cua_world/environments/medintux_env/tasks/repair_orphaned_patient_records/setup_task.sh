#!/bin/bash
set -euo pipefail
# Source shared utilities if available, otherwise define basics
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { :; }
fi

echo "=== Setting up repair_orphaned_patient_records task ==="

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running and ready
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3
for i in $(seq 1 20); do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready"
        break
    fi
    sleep 2
done

# Generate 5 random UUIDs
GUID1=$(cat /proc/sys/kernel/random/uuid) # DUPONT (Orphan)
GUID2=$(cat /proc/sys/kernel/random/uuid) # MARTIN (Indexed)
GUID3=$(cat /proc/sys/kernel/random/uuid) # BERNARD (Orphan)
GUID4=$(cat /proc/sys/kernel/random/uuid) # LEROY (Indexed)
GUID5=$(cat /proc/sys/kernel/random/uuid) # MOREAU (Orphan)

# Save configuration for export_result.sh to use later
cat > /tmp/task_config.sh << EOF
export GUID_DUPONT="$GUID1"
export GUID_MARTIN="$GUID2"
export GUID_BERNARD="$GUID3"
export GUID_LEROY="$GUID4"
export GUID_MOREAU="$GUID5"
EOF
chmod 644 /tmp/task_config.sh

echo "Generated GUIDs:"
echo "  DUPONT: $GUID1 (Orphan)"
echo "  MARTIN: $GUID2 (Indexed)"
echo "  BERNARD: $GUID3 (Orphan)"
echo "  LEROY: $GUID4 (Indexed)"
echo "  MOREAU: $GUID5 (Orphan)"

# Clean up previous test data
mysql -u root DrTuxTest << 'CLEANUP'
DELETE FROM fchpat WHERE FchPat_NomFille IN ('DUPONT','MARTIN','BERNARD','LEROY','MOREAU');
DELETE FROM IndexNomPrenom WHERE FchGnrl_NomDos IN ('DUPONT','MARTIN','BERNARD','LEROY','MOREAU');
CLEANUP

# Insert 5 patients into fchpat (The Detail Table)
mysql -u root DrTuxTest << FCHPAT_EOF
INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_Titre, FchPat_Adresse, FchPat_CP, FchPat_Ville, FchPat_Tel1, FchPat_NumSS)
VALUES
('$GUID1', 'DUPONT', '1965-03-12', 'F', 'Mme', '14 Rue de la Paix', 75002, 'Paris', '0145678901', '265037502312345'),
('$GUID2', 'MARTIN', '1978-07-22', 'H', 'M.', '8 Champs-Elysees', 75008, 'Paris', '0156789012', '178077500823456'),
('$GUID3', 'BERNARD', '1952-11-08', 'F', 'Mme', '23 Rue Hugo', 69002, 'Lyon', '0478901234', '252116900234567'),
('$GUID4', 'LEROY', '1990-04-15', 'H', 'M.', '5 Place Bellecour', 69002, 'Lyon', '0478012345', '190046900245678'),
('$GUID5', 'MOREAU', '1985-09-30', 'F', 'Mme', '17 Cours Mirabeau', 13100, 'Aix', '0442345678', '285091310056789');
FCHPAT_EOF

# Insert ONLY 2 patients into IndexNomPrenom (The Search Index)
# The other 3 are deliberately omitted to create the "orphan" state
mysql -u root DrTuxTest << INDEX_EOF
INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type)
VALUES
('$GUID2', 'MARTIN', 'Pierre', 'Dossier'),
('$GUID4', 'LEROY', 'Jean-Paul', 'Dossier');
INDEX_EOF

# Create the helper CSV file for the agent
cat > /home/ga/orphan_firstnames.csv << CSV_EOF
GUID,FirstName
$GUID1,Marie
$GUID2,Pierre
$GUID3,Sophie
$GUID4,Jean-Paul
$GUID5,Isabelle
CSV_EOF
chown ga:ga /home/ga/orphan_firstnames.csv

# Record initial state of the index
INITIAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('$GUID1','$GUID2','$GUID3','$GUID4','$GUID5')")
echo "$INITIAL_COUNT" > /tmp/initial_index_count.txt

# Remove any previous report
rm -f /home/ga/orphan_repair_report.txt

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="