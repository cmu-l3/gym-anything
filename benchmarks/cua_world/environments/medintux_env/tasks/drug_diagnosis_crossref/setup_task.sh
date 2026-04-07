#!/bin/bash
set -e
echo "=== Setting up Drug-Diagnosis Crossref Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
if ! pgrep mysqld > /dev/null; then
    echo "Starting MySQL..."
    service mysql start
    sleep 5
fi

# Verify databases exist
echo "Verifying databases..."
DBS=$(mysql -u root -e "SHOW DATABASES;" 2>/dev/null)

if echo "$DBS" | grep -q "MedicaTuxTest" && echo "$DBS" | grep -q "CIM10Test"; then
    echo "Required databases found."
else
    echo "ERROR: Required databases (MedicaTuxTest, CIM10Test) not found!"
    # Attempt to reload if missing (failsafe)
    if [ -f "/home/ga/.wine/drive_c/MedinTux-2.16/set_bases/bin/SqlCreateTable/Dump_MedicaTuxTest.sql" ]; then
        echo "Reloading MedicaTuxTest..."
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS MedicaTuxTest;"
        mysql -u root MedicaTuxTest < "/home/ga/.wine/drive_c/MedinTux-2.16/set_bases/bin/SqlCreateTable/Dump_MedicaTuxTest.sql"
    fi
    if [ -f "/home/ga/.wine/drive_c/MedinTux-2.16/set_bases/bin/SqlCreateTable/Dump_CIM10Test.sql" ]; then
        echo "Reloading CIM10Test..."
        mysql -u root -e "CREATE DATABASE IF NOT EXISTS CIM10Test;"
        mysql -u root CIM10Test < "/home/ga/.wine/drive_c/MedinTux-2.16/set_bases/bin/SqlCreateTable/Dump_CIM10Test.sql"
    fi
fi

# Clean up any previous report
rm -f /home/ga/drug_diagnosis_crossref_report.txt

# Create a 'hint' file acting as a work order from the clinic head
cat > /home/ga/Desktop/Work_Order.txt << EOF
URGENT: Formulary Analysis Request

We need to verify if our drug database covers all major diagnostic categories.
Please connect to the database server and generate a cross-reference report.

Sources:
- Drugs: MedicaTuxTest DB (look for ATC codes)
- Diagnoses: CIM10Test DB (look for Chapters)

Output:
A text file report at ~/drug_diagnosis_crossref_report.txt listing:
1. ATC Code (Level 1)
2. Corresponding CIM10 Chapter
3. Counts of items in each
4. Any identified gaps

Thanks,
Dr. Tux
EOF

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="