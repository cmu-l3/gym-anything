#!/bin/bash
set -e
echo "=== Setting up Population Health Age Pyramid Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Ensure target directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Check current patient count
COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null || echo 0)
echo "Current patient count: $COUNT"

# If fewer than 50 patients, inject synthetic data to ensure a good chart
if [ "$COUNT" -lt 50 ]; then
    echo "Injecting synthetic patient data for better visualization..."
    
    # Create a python script to generate SQL inserts
    cat > /tmp/gen_data.py << 'EOF'
import uuid
import random
import datetime

# Age distribution weights to make it look realistic (more young/middle, fewer old)
ages = []
for age in range(0, 100):
    # Simple curve
    weight = 100 - age if age < 80 else 10
    ages.extend([age] * weight)

sexes = ['M', 'F']

print("INSERT INTO fchpat (FchPat_GUID_Doss, FchPat_NomFille, FchPat_Nee, FchPat_Sexe, FchPat_NumSS) VALUES")
values = []

current_year = datetime.date.today().year

for i in range(150):
    guid = str(uuid.uuid4())
    age = random.choice(ages)
    birth_year = current_year - age
    birth_month = random.randint(1, 12)
    birth_day = random.randint(1, 28)
    dob = f"{birth_year}-{birth_month:02d}-{birth_day:02d}"
    sex = random.choice(sexes)
    
    # Minimal fields required
    values.append(f"('{guid}', 'TestPatient_{i}', '{dob}', '{sex}', '1234567890123')")

print(",\n".join(values) + ";")
EOF

    # Execute generation and insert
    python3 /tmp/gen_data.py > /tmp/insert_data.sql
    mysql -u root DrTuxTest < /tmp/insert_data.sql 2>/dev/null || echo "Data injection warning (duplicates ignored)"
    rm -f /tmp/gen_data.py /tmp/insert_data.sql
fi

FINAL_COUNT=$(mysql -u root DrTuxTest -N -e "SELECT COUNT(*) FROM fchpat" 2>/dev/null)
echo "Final patient count: $FINAL_COUNT"

# Ensure Python dependencies for data science are installed
# (pandas/matplotlib are standard in the environment, but good to check)
if ! python3 -c "import pandas, matplotlib" 2>/dev/null; then
    echo "Installing pandas/matplotlib..."
    pip3 install pandas matplotlib --break-system-packages 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="