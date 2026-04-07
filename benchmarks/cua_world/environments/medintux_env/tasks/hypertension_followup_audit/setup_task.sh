#!/bin/bash
set -e
echo "=== Setting up Hypertension Follow-up Audit ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

echo "Configuring Database Data..."

# Create the Rubriques table if it doesn't exist (ensuring schema availability for the task)
# We use a simplified schema compatible with the task description if the real one is too complex or missing
mysql -u root DrTuxTest <<EOF
CREATE TABLE IF NOT EXISTS Rubriques (
    Rb_PrimKey INT AUTO_INCREMENT PRIMARY KEY,
    RbDate_IDDos VARCHAR(50),
    RbDate_Date DATE,
    RbDate_Type VARCHAR(50),
    RbDate_Texte TEXT,
    INDEX (RbDate_IDDos)
);
EOF

# Define Patients and insert them into IndexNomPrenom and Rubriques
# We use GUIDs for linking
GUID_DUBOIS="GUID-DUBOIS-001"
GUID_ROUX="GUID-ROUX-002"
GUID_LEGRAND="GUID-LEGRAND-003"
GUID_PETIT="GUID-PETIT-004"
GUID_BLANC="GUID-BLANC-005"

# Clean up previous run data
mysql -u root DrTuxTest -e "DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos IN ('$GUID_DUBOIS', '$GUID_ROUX', '$GUID_LEGRAND', '$GUID_PETIT', '$GUID_BLANC');"
mysql -u root DrTuxTest -e "DELETE FROM Rubriques WHERE RbDate_IDDos IN ('$GUID_DUBOIS', '$GUID_ROUX', '$GUID_LEGRAND', '$GUID_PETIT', '$GUID_BLANC');"

# 1. Paul DUBOIS (Target: HTA, 3 visits, Avg 45.0)
# Intervals: Jan 1 -> Feb 1 (31 days), Feb 1 -> Apr 1 (59 days). Avg = 45.
mysql -u root DrTuxTest <<EOF
INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID_DUBOIS', 'DUBOIS', 'Paul', 'Dossier');
INSERT INTO Rubriques (RbDate_IDDos, RbDate_Date, RbDate_Texte) VALUES 
('$GUID_DUBOIS', '2023-01-01', 'Patient presents with HTA. BP 150/90.'),
('$GUID_DUBOIS', '2023-02-01', 'Follow up visit. BP stable.'),
('$GUID_DUBOIS', '2023-04-01', 'Prescription refill for hypertension meds.');
EOF

# 2. Julie ROUX (Target: HTA, 2 visits, Avg 10.0)
# Intervals: Jan 1 -> Jan 11 (10 days). Avg = 10.
mysql -u root DrTuxTest <<EOF
INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID_ROUX', 'ROUX', 'Julie', 'Dossier');
INSERT INTO Rubriques (RbDate_IDDos, RbDate_Date, RbDate_Texte) VALUES 
('$GUID_ROUX', '2023-01-01', 'Diagnosis: Hypertension confirmed.'),
('$GUID_ROUX', '2023-01-11', 'Blood pressure check. Improving.');
EOF

# 3. Marc LEGRAND (Distractor: No HTA keywords)
mysql -u root DrTuxTest <<EOF
INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID_LEGRAND', 'LEGRAND', 'Marc', 'Dossier');
INSERT INTO Rubriques (RbDate_IDDos, RbDate_Date, RbDate_Texte) VALUES 
('$GUID_LEGRAND', '2023-03-01', 'Routine checkup. No known allergies.'),
('$GUID_LEGRAND', '2023-03-15', 'Flu symptoms. Prescribed rest.');
EOF

# 4. Sophie PETIT (Exclude: HTA but < 2 visits)
mysql -u root DrTuxTest <<EOF
INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID_PETIT', 'PETIT', 'Sophie', 'Dossier');
INSERT INTO Rubriques (RbDate_IDDos, RbDate_Date, RbDate_Texte) VALUES 
('$GUID_PETIT', '2023-05-01', 'History of HTA. Monitoring required.');
EOF

# 5. Jean BLANC (Exclude: HTA but visits on same day -> 1 distinct date)
mysql -u root DrTuxTest <<EOF
INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID_BLANC', 'BLANC', 'Jean', 'Dossier');
INSERT INTO Rubriques (RbDate_IDDos, RbDate_Date, RbDate_Texte) VALUES 
('$GUID_BLANC', '2023-01-01', 'Complaint: High BP.'),
('$GUID_BLANC', '2023-01-01', 'Lab results reviewed.');
EOF

# Launch MedinTux Manager to ensure environment is live (though task is DB focused)
launch_medintux_manager

# Create Documents directory
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="