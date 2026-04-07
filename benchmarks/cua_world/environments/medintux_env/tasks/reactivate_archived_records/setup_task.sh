#!/bin/bash
set -e
echo "=== Setting up Reactivate Archived Records Task ==="

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

DB_NAME="DrTuxTest"

echo "Setting up database state..."

# 1. Create the Archive Table
mysql -u root $DB_NAME <<EOF
DROP TABLE IF EXISTS ArchivedPatients;
CREATE TABLE ArchivedPatients (
    GUID VARCHAR(64) PRIMARY KEY,
    Nom VARCHAR(50),
    Prenom VARCHAR(50),
    DateNaissance DATE,
    Sexe CHAR(1),
    Adresse VARCHAR(100),
    CodePostal VARCHAR(10),
    Ville VARCHAR(50),
    Tel VARCHAR(20),
    NumSS VARCHAR(20)
);
EOF

# 2. Generate Synthetic Data
# We will insert 10 records. 3 will be our targets.
# Using python to generate SQL for better string handling
python3 -c "
import uuid
import random
import datetime

names = [
    ('MARTIN', 'Sophie'), ('BERNARD', 'Michel'), ('THOMAS', 'David'),
    ('PETIT', 'Isabelle'), ('ROBERT', 'Jean'), ('RICHARD', 'Helene'),
    ('DURAND', 'Pierre'), ('DUBOIS', 'Marie'), ('MOREAU', 'Luc'), ('LAURENT', 'Claire')
]

# Cities and Zips
locs = [('Paris', '75001'), ('Lyon', '69002'), ('Marseille', '13001'), ('Bordeaux', '33000')]

sqls = []
targets = []

for i, (last, first) in enumerate(names):
    guid = str(uuid.uuid4()).upper()
    dob = f'{random.randint(1950, 1990)}-{random.randint(1,12):02d}-{random.randint(1,28):02d}'
    sex = 'F' if i % 2 == 0 else 'M'
    city, zip_code = random.choice(locs)
    addr = f'{random.randint(1,100)} Rue Principal'
    tel = f'06{random.randint(10000000, 99999999)}'
    ssn = f'1{dob[2:4]}{dob[5:7]}{zip_code}001{random.randint(10,99)}'
    
    sqls.append(f\"INSERT INTO ArchivedPatients VALUES ('{guid}', '{last}', '{first}', '{dob}', '{sex}', '{addr}', '{zip_code}', '{city}', '{tel}', '{ssn}');\")
    
    # Pick first 3 as targets
    if i < 3:
        targets.append((guid, last, first))

# Output SQL
print('\n'.join(sqls))

# Output Targets to a temp file for the setup script to read
with open('/tmp/targets.txt', 'w') as f:
    for t in targets:
        f.write(f'{t[0]}|{t[1]}|{t[2]}\n')
" > /tmp/insert_archive.sql

# Execute the inserts
mysql -u root $DB_NAME < /tmp/insert_archive.sql

# 3. Create the Request File
echo "Creating request file..."
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/restore_requests.txt
touch /home/ga/Documents/restore_requests.txt

echo "URGENT: Please reactivate the following patient records from the archive:" >> /home/ga/Documents/restore_requests.txt
echo "" >> /home/ga/Documents/restore_requests.txt

# Read targets and format request file
TARGET_GUIDS=()
while IFS='|' read -r guid last first; do
    echo "- $last $first" >> /home/ga/Documents/restore_requests.txt
    TARGET_GUIDS+=("$guid")
    
    # Ensure they DO NOT exist in active tables (clean state)
    mysql -u root $DB_NAME -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$guid'"
    mysql -u root $DB_NAME -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$guid'"
    
done < /tmp/targets.txt

# Save target GUIDs for verification later
printf "%s\n" "${TARGET_GUIDS[@]}" > /tmp/target_guids.txt

# 4. Launch Application (for visual verification context)
# We launch it so the agent *could* check if the patients appear after restore
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Requests file created at /home/ga/Documents/restore_requests.txt"
cat /home/ga/Documents/restore_requests.txt