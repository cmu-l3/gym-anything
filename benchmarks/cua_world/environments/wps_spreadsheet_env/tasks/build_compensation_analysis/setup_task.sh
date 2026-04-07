#!/bin/bash
echo "=== Setting up build_compensation_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create ground truth directory
mkdir -p /var/lib/task_ground_truth
chmod 700 /var/lib/task_ground_truth

# Download real IBM HR Dataset
CSV_URL="https://raw.githubusercontent.com/datasciencedojo/datasets/master/IBM%20HR%20Analytics%20Employee%20Attrition%20%26%20Performance.csv"
DATA_DIR="/tmp/hr_data"
mkdir -p "$DATA_DIR"

echo "Downloading dataset..."
if ! curl -sL --connect-timeout 15 --max-time 60 "$CSV_URL" -o "$DATA_DIR/ibm_hr.csv" 2>/dev/null; then
    echo "WARN: Download failed, generating fallback HR data..."
    python3 << 'FALLBACK_PYEOF'
import csv, random
random.seed(42)
departments = ['Human Resources', 'Research & Development', 'Sales']
roles = {'Human Resources': ['HR Rep', 'HR Manager'], 'Research & Development': ['Lab Tech', 'Scientist', 'Research Director'], 'Sales': ['Sales Rep', 'Sales Executive', 'Sales Manager']}
fields = ['Life Sciences', 'Medical', 'Marketing', 'Technical Degree', 'Human Resources', 'Other']
with open('/tmp/hr_data/ibm_hr.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['EmployeeNumber','Department','JobRole','MonthlyIncome','TotalWorkingYears','YearsAtCompany','PerformanceRating','Attrition','JobLevel','OverTime','Gender','Age','EducationField','MaritalStatus'])
    for i in range(1, 1471):
        dept = random.choice(departments)
        role = random.choice(roles[dept])
        level = random.randint(1,5)
        income = random.randint(1000, 20000)
        yrs_total = random.randint(0, 40)
        yrs_co = random.randint(0, min(yrs_total, 30))
        perf = random.choice([3,4])
        att = random.choice(['Yes','No','No','No','No'])
        ot = random.choice(['Yes','No'])
        gender = random.choice(['Male','Female'])
        age = random.randint(18,60)
        field = random.choice(fields)
        marital = random.choice(['Single','Married','Divorced'])
        w.writerow([i, dept, role, income, yrs_total, yrs_co, perf, att, level, ot, gender, age, field, marital])
FALLBACK_PYEOF
    echo "Fallback data generated with 1470 rows"
fi

# Use Python to process the CSV, create the starting Excel file, and compute ground truth
python3 << 'PYEOF'
import csv
import json