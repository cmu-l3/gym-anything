#!/bin/bash
set -e
echo "=== Setting up Bulk Import Risks Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Record Initial Risk Count
INITIAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM risks WHERE deleted=0;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_risk_count.txt

# 3. Create the CSV file on Desktop with realistic data
# Note: Eramba CSV import can be finicky, so we provide a clean, standard CSV format
cat > /home/ga/Desktop/legacy_clinic_risks.csv <<EOF
Risk Name,Risk Detail,Threat Agent,Weakness
Unpatched Legacy MRI Systems,MRI control workstations are running Windows XP and cannot be patched.,Ransomware gangs targeting medical devices,End-of-life operating system with known exploits
Clinic WiFi Guest Access,Guest WiFi shares the same VLAN as medical records database.,Hackers using guest access to pivot,Lack of network segmentation
Paper Records Storage,Patient intake forms are stored in an unlocked cabinet in the lobby.,Physical theft or unauthorized viewing,Lack of physical access controls
Third-Party Lab Interface,Lab results API uses hardcoded credentials in plain text.,Interception of API traffic,Insecure authentication implementation
EOF

# Ensure the user owns the file
chown ga:ga /home/ga/Desktop/legacy_clinic_risks.csv
chmod 644 /home/ga/Desktop/legacy_clinic_risks.csv

# 4. Ensure Firefox is running and logged in
# We start on the Dashboard or Risks index to give the agent a fair start
ensure_firefox_eramba "http://localhost:8080/risks/index"

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Created CSV at /home/ga/Desktop/legacy_clinic_risks.csv"
echo "Initial risk count: $INITIAL_COUNT"