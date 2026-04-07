#!/bin/bash
set -e
echo "=== Setting up create_patient_view task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
echo "Starting MySQL..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready."
        break
    fi
    sleep 1
done

# Prepare database state
echo "Preparing DrTuxTest database..."

# Ensure the database exists (using the MedinTux demo data structure)
mysql -u root -e "CREATE DATABASE IF NOT EXISTS DrTuxTest;"

# Drop the view if it already exists (to ensure the agent actually creates it)
mysql -u root DrTuxTest -e "DROP VIEW IF EXISTS vue_patients_complete;"

# Ensure there is at least one patient 'Dossier' to verify data retrieval later
# Check if data exists in IndexNomPrenom
COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM IndexNomPrenom WHERE FchGnrl_Type='Dossier'" 2>/dev/null || echo "0")
if [ "$COUNT" -eq "0" ]; then
    echo "Injecting sample patient data..."
    # Insert sample patient if database is empty
    GUID="TEST-GUID-001"
    mysql -u root DrTuxTest -e "INSERT INTO IndexNomPrenom (FchGnrl_IDDos, FchGnrl_NomDos, FchGnrl_Prenom, FchGnrl_Type) VALUES ('$GUID', 'TEST', 'Patient', 'Dossier');"
    mysql -u root DrTuxTest -e "CREATE TABLE IF NOT EXISTS fchpat (FchPat_GUID_Doss VARCHAR(64), FchPat_Nee DATE, FchPat_Sexe CHAR(1), FchPat_Adresse VARCHAR(255), FchPat_CP VARCHAR(10), FchPat_Ville VARCHAR(100), FchPat_Tel1 VARCHAR(20), FchPat_NumSS VARCHAR(20));"
    mysql -u root DrTuxTest -e "INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_Nee, FchPat_Sexe, FchPat_Ville) VALUES ('$GUID', '1980-01-01', 'M', 'Paris');"
fi

# Open a terminal for the agent to work in
echo "Launching terminal..."
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30 -title 'Terminal - MySQL Task' &"
    sleep 2
fi

# Maximize/Focus terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="