#!/bin/bash
echo "=== Setting up HR Pay Equity Statistical Audit Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null || echo "not_found")
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running."

echo "Cleaning up previous run artifacts..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

# Create HR_ANALYST user
echo "Creating HR_ANALYST user..."
oracle_query "CREATE USER hr_analyst IDENTIFIED BY HrAnalyst2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO hr_analyst;
GRANT RESOURCE TO hr_analyst;
GRANT CREATE VIEW TO hr_analyst;
GRANT CREATE PROCEDURE TO hr_analyst;
GRANT CREATE SESSION TO hr_analyst;
GRANT CREATE TABLE TO hr_analyst;
EXIT;" "system"

# Create table
echo "Creating EMPLOYEE_STATS table..."
oracle_query "CREATE TABLE hr_analyst.employee_stats (
    employee_number NUMBER PRIMARY KEY,
    age NUMBER,
    attrition VARCHAR2(3),
    department VARCHAR2(50),
    distance_from_home NUMBER,
    education NUMBER,
    education_field VARCHAR2(50),
    gender VARCHAR2(10),
    job_involvement NUMBER,
    job_level NUMBER,
    job_role VARCHAR2(50),
    job_satisfaction NUMBER,
    marital_status VARCHAR2(20),
    monthly_income NUMBER,
    num_companies_worked NUMBER,
    over_time VARCHAR2(3),
    percent_salary_hike NUMBER,
    performance_rating NUMBER,
    total_working_years NUMBER,
    years_at_company NUMBER,
    years_in_current_role NUMBER,
    years_since_last_promotion NUMBER,
    years_with_curr_manager NUMBER
);
EXIT;" "system"

# Download and parse IBM HR Dataset using Python, fall back to hardcoded if network fails
echo "Loading real HR data into Oracle..."
cat > /tmp/load_hr_data.py << 'EOF'
import urllib.request
import csv
import sys

URL = "https://raw.githubusercontent.com/pavopax/ibm-hr-analytics-attrition-dataset/master/WA_Fn-UseC_-HR-Employee-Attrition.csv"
OUTPUT_FILE = "/tmp/hr_inserts.sql"

fallback_data = [
    "1,41,Yes,Sales,1,2,Life Sciences,Female,3,2,Sales Executive,4,Single,5993,8,Yes,11,3,8,6,4,0,5",
    "2,49,No,Research & Development,8,1,Life Sciences,Male,2,2,Research Scientist,2,Married,5130,1,No,23,4,10,10,7,1,7",
    "3,37,Yes,Research & Development,2,2,Other,Male,2,1,Laboratory Technician,3,Single,2090,6,Yes,15,3,7,0,0,0,0",
    "4,33,No,Research & Development,3,4,Life Sciences,Female,3,1,Research Scientist,3,Married,2909,1,Yes,11,3,8,8,7,3,0",
    "5,27,No,Research & Development,2,1,Medical,Male,3,1,Laboratory Technician,2,Married,3468,9,No,12,3,6,2,2,2,2",
    "6,32,No,Research & Development,2,2,Life Sciences,Male,3,1,Laboratory Technician,4,Single,3068,0,No,13,3,8,7,7,3,6",
    "7,59,No,Research & Development,3,3,Medical,Female,4,1,Laboratory Technician,1,Married,2670,4,Yes,20,4,12,1,0,0,0",
    "8,30,No,Research & Development,24,1,Life Sciences,Male,3,1,Laboratory Technician,3,Divorced,2693,1,No,22,4,1,1,0,0,0",
    "9,38,No,Research & Development,23,3,Life Sciences,Male,2,3,Manufacturing Director,3,Single,9526,0,No,21,4,10,9,7,1,8",
    "10,36,No,Research & Development,27,3,Medical,Male,3,2,Healthcare Representative,3,Married,5237,6,No,13,3,17,7,7,7,7"
]

try:
    print("Downloading IBM HR Attrition dataset...")
    req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0'})
    response = urllib.request.urlopen(req, timeout=10)
    lines = [line.decode('utf-8') for line in response.readlines()]
    reader = csv.DictReader(lines)
    rows = list(reader)
    print(f"Downloaded {len(rows)} records.")
except Exception as e:
    print(f"Download failed: {e}. Using fallback data.")
    reader = csv.reader(fallback_data)
    headers = ["EmployeeNumber","Age","Attrition","Department","DistanceFromHome","Education","EducationField","Gender","JobInvolvement","JobLevel","JobRole","JobSatisfaction","MaritalStatus","MonthlyIncome","NumCompaniesWorked","OverTime","PercentSalaryHike","PerformanceRating","TotalWorkingYears","YearsAtCompany","YearsInCurrentRole","YearsSinceLastPromotion","YearsWithCurrManager"]
    rows = [dict(zip(headers, r)) for r in reader]

with open(OUTPUT_FILE, 'w') as f:
    f.write("SET DEFINE OFF;\n")
    f.write("BEGIN\n")
    for r in rows:
        # Avoid huge script execution by limiting to first 500 rows if downloaded
        if int(r.get('EmployeeNumber', 1000)) > 500: continue
        sql = f"""  INSERT INTO hr_analyst.employee_stats VALUES ({r['EmployeeNumber']}, {r['Age']}, '{r['Attrition']}', '{r['Department'].replace("'","''")}', {r['DistanceFromHome']}, {r['Education']}, '{r['EducationField'].replace("'","''")}', '{r['Gender']}', {r['JobInvolvement']}, {r['JobLevel']}, '{r['JobRole'].replace("'","''")}', {r['JobSatisfaction']}, '{r['MaritalStatus']}', {r['MonthlyIncome']}, {r['NumCompaniesWorked']}, '{r['OverTime']}', {r['PercentSalaryHike']}, {r['PerformanceRating']}, {r['TotalWorkingYears']}, {r['YearsAtCompany']}, {r['YearsInCurrentRole']}, {r['YearsSinceLastPromotion']}, {r['YearsWithCurrManager']});\n"""
        f.write(sql)
    f.write("  COMMIT;\nEND;\n/\nEXIT;\n")
print("SQL insert script generated.")
EOF

python3 /tmp/load_hr_data.py
sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 < /tmp/hr_inserts.sql

# Pre-configure SQL Developer Connection
ensure_hr_connection "HR Analyst DB" "hr_analyst" "HrAnalyst2024"

# Set up exports directory
mkdir -p /home/ga/Documents/exports
chown ga:ga /home/ga/Documents/exports

# Maximize SQL Developer if open
WID=$(DISPLAY=:1 wmctrl -l | grep -iE "sql developer|oracle sql" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="