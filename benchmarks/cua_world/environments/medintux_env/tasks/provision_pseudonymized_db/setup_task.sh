#!/bin/bash
set -e
echo "=== Setting up provision_pseudonymized_db task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
service mysql start 2>/dev/null || systemctl start mysql 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# Prepare Source Database (DrTuxTest)
# We ensure it exists and has data. If empty, we populate it with the demo data or synthetic data.
echo "Checking source database..."
mysql -u root -e "CREATE DATABASE IF NOT EXISTS DrTuxTest;"

# Check if tables exist
TABLES_EXIST=$(mysql -u root DrTuxTest -N -e "SHOW TABLES LIKE 'IndexNomPrenom';" | wc -l)

if [ "$TABLES_EXIST" -eq 0 ]; then
    echo "Restoring DrTuxTest from dump or creating schema..."
    # Try to load from standard location if available
    if [ -f "/opt/medintux/DrTuxTest_demo.sql" ]; then
        mysql -u root DrTuxTest < "/opt/medintux/DrTuxTest_demo.sql"
    else
        # Create schema manually if dump missing
        mysql -u root DrTuxTest <<EOF
CREATE TABLE IF NOT EXISTS IndexNomPrenom (
  FchGnrl_IDDos varchar(50) NOT NULL,
  FchGnrl_NomDos varchar(50) DEFAULT NULL,
  FchGnrl_Prenom varchar(50) DEFAULT NULL,
  FchGnrl_Type varchar(50) DEFAULT 'Dossier',
  PRIMARY KEY (FchGnrl_IDDos)
);
CREATE TABLE IF NOT EXISTS fchpat (
  FchPat_GUID_Doss varchar(50) NOT NULL,
  FchPat_NomFille varchar(50) DEFAULT NULL,
  FchPat_Nee date DEFAULT NULL,
  FchPat_Sexe char(1) DEFAULT NULL,
  FchPat_Titre varchar(10) DEFAULT NULL,
  FchPat_Adresse varchar(255) DEFAULT NULL,
  FchPat_CP varchar(10) DEFAULT NULL,
  FchPat_Ville varchar(100) DEFAULT NULL,
  FchPat_Tel1 varchar(20) DEFAULT NULL,
  FchPat_Tel2 varchar(20) DEFAULT NULL,
  FchPat_NumSS varchar(20) DEFAULT NULL,
  PRIMARY KEY (FchPat_GUID_Doss)
);
EOF
    fi
fi

# Ensure there is sufficient data (insert synthetic patients if needed)
COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'")
if [ "$COUNT" -lt 10 ]; then
    echo "Inserting synthetic patient data..."
    mysql -u root DrTuxTest <<EOF
INSERT IGNORE INTO IndexNomPrenom VALUES 
('UUID-1', 'DUPONT', 'Jean', 'Dossier'),
('UUID-2', 'MARTIN', 'Sophie', 'Dossier'),
('UUID-3', 'DURAND', 'Pierre', 'Dossier'),
('UUID-4', 'LEROY', 'Alice', 'Dossier'),
('UUID-5', 'MOREAU', 'Lucas', 'Dossier');

INSERT IGNORE INTO fchpat VALUES
('UUID-1', 'DUPONT', '1980-01-01', 'M', 'M.', '10 Rue de Paris', '75001', 'Paris', '0102030405', '', '1800175001001'),
('UUID-2', 'MARTIN', '1990-05-15', 'F', 'Mme', '20 Avenue des Champs', '69002', 'Lyon', '0607080910', '', '2900569002002'),
('UUID-3', 'DURAND', '1975-12-31', 'M', 'M.', '5 Boulevard Gambetta', '13001', 'Marseille', '0491000000', '', '1751213001003'),
('UUID-4', 'LEROY', '1985-07-20', 'F', 'Mme', '1 Place Kleber', '67000', 'Strasbourg', '0388000000', '', '2850767000004'),
('UUID-5', 'MOREAU', '2000-03-10', 'M', 'M.', '15 Rue du Port', '33000', 'Bordeaux', '0556000000', '', '1000333000005');
EOF
fi

# Record Source Checksum for verification (hash of names to detect modification)
echo "Recording source database state..."
SOURCE_CHECKSUM=$(mysql -u root DrTuxTest -N -e "SELECT MD5(GROUP_CONCAT(FchGnrl_NomDos ORDER BY FchGnrl_IDDos)) FROM IndexNomPrenom;")
echo "$SOURCE_CHECKSUM" > /tmp/source_db_checksum.txt

# Clean Slate: Drop Target DB if it exists
mysql -u root -e "DROP DATABASE IF EXISTS DrTuxResearch;"

# Open a terminal for the agent
su - ga -c "xterm -geometry 80x24+10+10 &"

echo "=== Setup complete ==="