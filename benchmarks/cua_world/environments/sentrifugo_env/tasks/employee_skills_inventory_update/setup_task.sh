#!/bin/bash
echo "=== Setting up employee_skills_inventory_update task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Wait for Sentrifugo web interface to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Find the exact table names for employee education, experience, and skills
ED_TABLE=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SHOW TABLES LIKE '%empeducation%';" | head -n 1)
EX_TABLE=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SHOW TABLES LIKE '%empexperience%';" | head -n 1)
SK_TABLE=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SHOW TABLES LIKE '%empskill%';" | head -n 1)

# Default to known names if lookup fails
ED_TABLE=${ED_TABLE:-main_empeducation}
EX_TABLE=${EX_TABLE:-main_empexperience}
SK_TABLE=${SK_TABLE:-main_empskills}

# Save table names for the export script
echo "$ED_TABLE" > /tmp/ed_table_name.txt
echo "$EX_TABLE" > /tmp/ex_table_name.txt
echo "$SK_TABLE" > /tmp/sk_table_name.txt

# Clean up any existing records for these three users to ensure a clean slate and idempotency
UIDS=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT id FROM main_users WHERE employeeId IN ('EMP002', 'EMP008', 'EMP011');" | tr '\n' ',' | sed 's/,$//')

if [ -n "$UIDS" ]; then
    echo "Clearing existing education/experience/skills for target users ($UIDS)..."
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $ED_TABLE WHERE user_id IN ($UIDS);" 2>/dev/null || true
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $EX_TABLE WHERE user_id IN ($UIDS);" 2>/dev/null || true
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $SK_TABLE WHERE user_id IN ($UIDS);" 2>/dev/null || true
fi

# Record initial counts to detect spamming (modifying all users instead of just the 3 target ones)
ED_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM $ED_TABLE;" 2>/dev/null || echo 0)
EX_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM $EX_TABLE;" 2>/dev/null || echo 0)
SK_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM $SK_TABLE;" 2>/dev/null || echo 0)

cat > /tmp/initial_counts.json << EOF
{
  "education": ${ED_COUNT//[^0-9]/},
  "experience": ${EX_COUNT//[^0-9]/},
  "skills": ${SK_COUNT//[^0-9]/}
}
EOF

# Drop dossier on the agent's Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/personnel_qualifications_dossier.txt << 'DOSSIER'
FEDERAL CONTRACT BID - SKILLS MATRIX UPDATE
URGENT: Required by EOD.

Please update the HRMS profiles for our three key personnel. The RFP requires their Sentrifugo profiles to reflect the following qualifications.

1. Emily Chen (EMP002)
   - EDUCATION: Master of Science in Mechanical Engineering
     Institution: Massachusetts Institute of Technology
     Year: 2018
   - EXPERIENCE: Project Engineer
     Company: General Electric
     Duration: 2018-05-01 to 2021-08-15
   - SKILLS: AutoCAD
     Years of Experience: 5

2. Michael Taylor (EMP008)
   - EDUCATION: Bachelor of Science in Electrical Engineering
     Institution: Georgia Institute of Technology
     Year: 2015
   - EXPERIENCE: Electrical Technician
     Company: Siemens
     Duration: 2015-06-01 to 2019-12-31
   - SKILLS: SCADA Systems
     Years of Experience: 7

3. David Anderson (EMP011)
   - EDUCATION: Master of Business Administration
     Institution: University of Pennsylvania
     Year: 2020
   - EXPERIENCE: Product Analyst
     Company: IBM
     Duration: 2020-07-01 to 2023-01-10
   - SKILLS: Agile Methodology
     Years of Experience: 4
DOSSIER

chown ga:ga /home/ga/Desktop/personnel_qualifications_dossier.txt

# Start Firefox and log in to Sentrifugo
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/employee"
sleep 4

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="