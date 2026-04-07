#!/bin/bash
set -e
echo "=== Setting up task: update_local_procedure_tariffs ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure MySQL is running and accessible
echo "Ensuring MySQL is running..."
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# 3. Setup the Database State (Reset to 2024 prices)
echo "Resetting database state..."
mysql -u root << 'MYSQL_EOF'
CREATE DATABASE IF NOT EXISTS DrTuxTest;
USE DrTuxTest;

DROP TABLE IF EXISTS CCAM_Local_Tarifs;
CREATE TABLE CCAM_Local_Tarifs (
    Code VARCHAR(10) PRIMARY KEY,
    Libelle VARCHAR(255),
    Tarif DECIMAL(10, 2)
);

-- Insert initial 2024 data
INSERT INTO CCAM_Local_Tarifs (Code, Libelle, Tarif) VALUES 
('CS', 'Consultation Spécialiste', 23.00),
('C', 'Consultation Médecine Générale', 25.00),
('APC', 'Avis Ponctuel Consultant', 50.00),
('TC', 'Téléconsultation', 25.00),
('K', 'Acte de chirurgie (coefficient)', 19.20),
('V', 'Visite à domicile', 33.00),
('COE', 'Consultation Obligatoire Enfant', 46.00),
('IMP', 'Implant contraceptif', 17.99);
MYSQL_EOF

# 4. Create the input CSV file
echo "Creating input CSV..."
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/tariffs_2025.csv << 'CSV_EOF'
Code,NewTarif
CS,30.00
APC,55.00
TC,25.00
K,20.00
IMP,25.50
CSV_EOF
chown ga:ga /home/ga/Documents/tariffs_2025.csv

# 5. Clean up previous results
rm -f /home/ga/Documents/update_log.txt

# 6. Open a terminal for the agent to work in
echo "Launching terminal..."
if ! pgrep -f "xterm" > /dev/null; then
    su - ga -c "DISPLAY=:1 xterm -geometry 100x30 -title 'Terminal - Task' &"
    sleep 2
fi

# 7. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="