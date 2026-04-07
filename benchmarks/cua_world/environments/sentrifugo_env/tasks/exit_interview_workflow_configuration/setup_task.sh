#!/bin/bash
echo "=== Setting up Exit Interview Workflow Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_time

# Wait for Sentrifugo web app to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Use a Python script to robustly manipulate the DB, handling exact table name variations
cat > /tmp/setup_exit_db.py << 'EOF'
import subprocess

def run_sql(sql):
    subprocess.run([
        'docker', 'exec', 'sentrifugo-db', 'mysql', 
        '-u', 'root', '-prootpass123', 'sentrifugo', '-e', sql
    ], stderr=subprocess.DEVNULL)

def query(sql):
    res = subprocess.run([
        'docker', 'exec', 'sentrifugo-db', 'mysql', 
        '-u', 'root', '-prootpass123', 'sentrifugo', '-N', '-B', '-e', sql
    ], capture_output=True, text=True)
    return [l.split('\t') for l in res.stdout.strip().split('\n') if l]

# Find relevant Exit module tables
tables = [r[0] for r in query("SHOW TABLES;")]
cat_table = next((t for t in tables if 'exit' in t and 'categor' in t), 'main_exitcategories')
q_table = next((t for t in tables if 'exit' in t and 'question' in t), 'main_exitquestions')
dept_table = next((t for t in tables if 'exit' in t and 'clearance' in t and 'dept' in t), 'main_exitclearancedepts')

# 1. Clean up any expected artifacts from previous runs
run_sql(f"DELETE FROM {q_table} WHERE question LIKE '%equipped with the necessary tools%';")
run_sql(f"DELETE FROM {q_table} WHERE question LIKE '%rate the physical working conditions%';")
run_sql(f"DELETE FROM {q_table} WHERE question LIKE '%compensation was competitive%';")
run_sql(f"DELETE FROM {q_table} WHERE question LIKE '%satisfied with the benefits%';")
run_sql(f"DELETE FROM {cat_table} WHERE categoryname IN ('Work Environment', 'Compensation');")
run_sql(f"DELETE FROM {dept_table} WHERE deptname IN ('IT & Devices', 'Facilities', 'Financial Accounts');")

# 2. Inject Legacy Questions (Agent must delete/deactivate these)
# First ensure old legacy questions are removed
run_sql(f"DELETE FROM {q_table} WHERE question IN ('How would you rate your manager?', 'Why are you leaving?', 'Would you recommend us?');")
run_sql(f"DELETE FROM {cat_table} WHERE categoryname = 'General Legacy';")

# Insert legacy category
run_sql(f"INSERT INTO {cat_table} (categoryname, isactive) VALUES ('General Legacy', 1);")

# Get the inserted category ID
cat_id_res = query("SELECT LAST_INSERT_ID();")
if cat_id_res and cat_id_res[0]:
    cat_id = cat_id_res[0][0]
    # Insert legacy questions
    for q in ['How would you rate your manager?', 'Why are you leaving?', 'Would you recommend us?']:
        run_sql(f"INSERT INTO {q_table} (question, category_id, isactive) VALUES ('{q}', {cat_id}, 1);")
        
print("Database cleanup and legacy data injection complete.")
EOF

python3 /tmp/setup_exit_db.py

# Create the configuration directive document
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/exit_process_config.txt << 'DOC'
ACME GLOBAL TECHNOLOGIES
Exit Interview Workflow Configuration Directive
=================================================
Effective: Q3 2026
Prepared by: Director of Human Resources

OBJECTIVE: Formalize the offboarding process by configuring the HRMS Exit module to collect structured feedback and ensure company assets are recovered. 

INSTRUCTIONS:
Log into Sentrifugo and navigate to the Exit module's settings to complete the following:

----- PART 1: CLEARANCE DEPARTMENTS -----
Create the following specific Clearance Departments (these must be set up in the Exit module, NOT as standard organization departments):
  1. IT & Devices
  2. Facilities
  3. Financial Accounts

----- PART 2: QUESTION CATEGORIES -----
Create the following Question Categories:
  1. Work Environment
  2. Compensation

----- PART 3: EXIT QUESTIONS -----
Create the following exact questions and assign them to the correct categories:

Category: Work Environment
  - Did you feel you were equipped with the necessary tools to perform your job?
  - How would you rate the physical working conditions?

Category: Compensation
  - Do you feel your compensation was competitive with the market?
  - Were you satisfied with the benefits package provided?

----- PART 4: LEGACY DATA CLEANUP -----
The system currently contains outdated generic exit questions. 
You MUST delete or deactivate all generic/legacy questions so that ONLY the 4 new questions listed above are active in the system.
DOC

chown ga:ga /home/ga/Desktop/exit_process_config.txt

# Launch browser to Sentrifugo dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="