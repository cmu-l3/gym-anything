#!/bin/bash
set -e
echo "=== Setting up Downtime Patient Card Generator task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Create necessary directories
mkdir -p /var/lib/medintux
chmod 777 /var/lib/medintux

# Clean up previous run artifacts
rm -rf /home/ga/downtime_cards
rm -f /home/ga/downtime_schedule.json

# ------------------------------------------------------------------
# 1. Insert Specific Test Patients into DrTuxTest
# ------------------------------------------------------------------
echo "Inserting test patients..."

# Patient 1: Standard case
GUID1="TEST-GUID-001"
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$GUID1'; DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID1';" 2>/dev/null || true
insert_patient "$GUID1" "MARTIN" "Jean" "1980-05-15" "M" "M." "10 Rue de la Paix" "75001" "Paris" "0102030405" "1800575001001"

# Patient 2: Missing phone (to test N/A handling)
GUID2="TEST-GUID-002"
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$GUID2'; DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID2';" 2>/dev/null || true
insert_patient "$GUID2" "DUBOIS" "Marie" "1995-11-30" "F" "Mme" "5 Avenue Foch" "69006" "Lyon" "" "2951169006002"

# Patient 3: Senior
GUID3="TEST-GUID-003"
mysql -u root DrTuxTest -e "DELETE FROM fchpat WHERE FchPat_GUID_Doss='$GUID3'; DELETE FROM IndexNomPrenom WHERE FchGnrl_IDDos='$GUID3';" 2>/dev/null || true
insert_patient "$GUID3" "LEROY" "Pierre" "1945-01-01" "M" "M." "Village" "33000" "Bordeaux" "0607080910" "1450133000003"

# ------------------------------------------------------------------
# 2. Create the Schedule JSON
# ------------------------------------------------------------------
echo "Generating schedule JSON..."
cat > /home/ga/downtime_schedule.json << EOF
{
  "date": "$(date +%Y-%m-%d)",
  "clinic_name": "Cabinet Medical DrTux",
  "appointments": [
    {
      "time": "09:00",
      "guid": "$GUID1",
      "reason": "Consultation generale"
    },
    {
      "time": "09:30",
      "guid": "$GUID2",
      "reason": "Vaccination"
    },
    {
      "time": "10:15",
      "guid": "$GUID3",
      "reason": "Suivi cardiologie"
    }
  ]
}
EOF
chown ga:ga /home/ga/downtime_schedule.json

# ------------------------------------------------------------------
# 3. Create Ground Truth Data (Hidden)
# ------------------------------------------------------------------
# We calculate expected ages here using python to ensure accuracy
# This file is used by the verifier
python3 -c "
import json
from datetime import date

def calculate_age(born_str):
    born = date.fromisoformat(born_str)
    today = date.today()
    return today.year - born.year - ((today.month, today.day) < (born.month, born.day))

patients = [
    {
        'guid': '$GUID1', 'lastname': 'MARTIN', 'firstname': 'Jean', 
        'dob': '1980-05-15', 'age': calculate_age('1980-05-15'),
        'phone': '0102030405', 'time': '09:00', 'filename': '0900_MARTIN_Jean.html'
    },
    {
        'guid': '$GUID2', 'lastname': 'DUBOIS', 'firstname': 'Marie', 
        'dob': '1995-11-30', 'age': calculate_age('1995-11-30'),
        'phone': 'N/A', 'time': '09:30', 'filename': '0930_DUBOIS_Marie.html'
    },
    {
        'guid': '$GUID3', 'lastname': 'LEROY', 'firstname': 'Pierre', 
        'dob': '1945-01-01', 'age': calculate_age('1945-01-01'),
        'phone': '0607080910', 'time': '10:15', 'filename': '1015_LEROY_Pierre.html'
    }
]

with open('/var/lib/medintux/downtime_ground_truth.json', 'w') as f:
    json.dump(patients, f, indent=2)
"

# ------------------------------------------------------------------
# 4. Final Environment Setup
# ------------------------------------------------------------------
# Ensure MedinTux Manager is technically running (even though this is a scripting task, 
# the environment implies the app is available)
ensure_medintux_running

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="