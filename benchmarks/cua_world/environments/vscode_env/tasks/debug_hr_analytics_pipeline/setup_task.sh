#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up HR Analytics Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/hr_analytics"

# Create directory structure
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{data,output,expected_output,pipeline,tests}

# Delete stale outputs BEFORE recording timestamp
rm -f /tmp/hr_analytics_result.json 2>/dev/null || true
rm -f /tmp/pipeline_stdout.log 2>/dev/null || true
rm -f /tmp/pytest_stdout.log 2>/dev/null || true
rm -rf "$WORKSPACE_DIR/output/"* 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# ──────────────────────────────────────────────────────────
# 1. Generate Realistic HR Data + Expected Output
# ──────────────────────────────────────────────────────────
echo "Generating HR dataset..."
cat > /tmp/generate_hr_data.py << 'PYGEN'
import random
import csv
import json
import os
from datetime import datetime, timedelta

import pandas as pd
import numpy as np

random.seed(42)
np.random.seed(42)

WORKSPACE = '/home/ga/workspace/hr_analytics'
DATA_DIR = os.path.join(WORKSPACE, 'data')
EXPECTED_DIR = os.path.join(WORKSPACE, 'expected_output')

# ── Department definitions ──
DEPTS = [
    {'id': 1,  'name': 'Engineering',       'budget': 4500000, 'size': 42},
    {'id': 2,  'name': 'Sales',             'budget': 3200000, 'size': 30},
    {'id': 3,  'name': 'Marketing',         'budget': 2800000, 'size': 22},
    {'id': 4,  'name': 'Finance',           'budget': 2100000, 'size': 16},
    {'id': 5,  'name': 'Human Resources',   'budget': 1800000, 'size': 14},
    {'id': 6,  'name': 'Operations',        'budget': 2500000, 'size': 22},
    {'id': 7,  'name': 'Legal',             'budget': 1600000, 'size': 10},
    {'id': 8,  'name': 'Product',           'budget': 2200000, 'size': 16},
    {'id': 9,  'name': 'Customer Support',  'budget': 1900000, 'size': 20},
    {'id': 10, 'name': 'Data Science',      'budget': 1400000, 'size': 8},
]

SALARY_RANGES = {
    1: (85000, 145000), 2: (55000, 110000), 3: (58000, 105000),
    4: (70000, 130000), 5: (55000, 95000),  6: (50000, 90000),
    7: (80000, 150000), 8: (75000, 135000), 9: (42000, 72000),
    10: (90000, 155000),
}

FIRST_NAMES = [
    'James', 'Mary', 'Robert', 'Patricia', 'John', 'Jennifer', 'Michael',
    'Linda', 'David', 'Elizabeth', 'William', 'Barbara', 'Richard', 'Susan',
    'Joseph', 'Jessica', 'Thomas', 'Sarah', 'Christopher', 'Karen',
    'Charles', 'Lisa', 'Daniel', 'Nancy', 'Matthew', 'Betty', 'Anthony',
    'Margaret', 'Mark', 'Sandra', 'Steven', 'Ashley', 'Paul', 'Dorothy',
    'Andrew', 'Kimberly', 'Joshua', 'Emily', 'Kenneth', 'Donna', 'Kevin',
    'Michelle', 'Brian', 'Carol', 'George', 'Amanda', 'Timothy', 'Melissa',
    'Ronald', 'Deborah', 'Edward', 'Stephanie', 'Jason', 'Rebecca',
    'Jeffrey', 'Sharon', 'Ryan', 'Laura', 'Jacob', 'Cynthia', 'Gary',
    'Kathleen', 'Nicholas', 'Amy', 'Eric', 'Angela', 'Jonathan', 'Shirley',
    'Stephen', 'Anna', 'Larry', 'Brenda', 'Justin', 'Pamela', 'Scott',
    'Emma', 'Brandon', 'Nicole', 'Benjamin', 'Helen', 'Samuel', 'Samantha',
    'Raymond', 'Katherine', 'Gregory', 'Christine', 'Frank', 'Debra',
    'Alexander', 'Rachel', 'Patrick', 'Carolyn', 'Jack', 'Janet', 'Dennis',
    'Catherine', 'Jerry', 'Maria', 'Tyler', 'Heather', 'Aaron', 'Diane',
    'Jose', 'Ruth', 'Nathan', 'Julie', 'Henry', 'Olivia', 'Douglas',
    'Joyce', 'Peter', 'Virginia', 'Adam', 'Victoria', 'Zachary', 'Kelly',
    'Walter', 'Lauren', 'Harold', 'Christina',
]

LAST_NAMES = [
    'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller',
    'Davis', 'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez',
    'Wilson', 'Anderson', 'Thomas', 'Taylor', 'Moore', 'Jackson', 'Martin',
    'Lee', 'Perez', 'Thompson', 'White', 'Harris', 'Sanchez', 'Clark',
    'Ramirez', 'Lewis', 'Robinson', 'Walker', 'Young', 'Allen', 'King',
    'Wright', 'Scott', 'Torres', 'Nguyen', 'Hill', 'Flores', 'Green',
    'Adams', 'Nelson', 'Baker', 'Hall', 'Rivera', 'Campbell', 'Mitchell',
    'Carter', 'Roberts', 'Gomez', 'Phillips', 'Evans', 'Turner', 'Diaz',
    'Parker', 'Cruz', 'Edwards', 'Collins', 'Reyes', 'Stewart', 'Morris',
    'Morales', 'Murphy', 'Cook', 'Rogers', 'Gutierrez', 'Ortiz', 'Morgan',
    'Cooper', 'Peterson', 'Bailey', 'Reed', 'Kelly', 'Howard', 'Ramos',
    'Kim', 'Cox', 'Ward', 'Richardson', 'Watson', 'Brooks', 'Chavez',
    'Wood', 'James', 'Bennett', 'Gray', 'Mendoza', 'Ruiz', 'Hughes',
    'Price', 'Alvarez', 'Castillo', 'Sanders', 'Patel', 'Myers', 'Long',
    'Ross', 'Foster', 'Jimenez', 'Powell', 'Jenkins', 'Perry',
]

Q1_START = datetime(2025, 1, 1)
Q1_END = datetime(2025, 3, 31)

# ── Generate 200 employees across departments ──
employees = []
emp_counter = 1
for dept in DEPTS:
    for _ in range(dept['size']):
        eid = f'EMP{emp_counter:04d}'
        emp_counter += 1
        employees.append({
            'employee_id': eid,
            'first_name': random.choice(FIRST_NAMES),
            'last_name': random.choice(LAST_NAMES),
            'email': f'{eid.lower()}@acmecorp.com',
            'department_id': dept['id'],
            'hire_date': '',
            'termination_date': '',
            'status': 'active',
            'gender': random.choice(['M', 'F']),
        })

# Shuffle to randomize status assignment across departments
random.shuffle(employees)

# Assign statuses: 12 new hires, 4 Q1-terminated, 23 pre-Q1 terminated, rest regular active
for i, emp in enumerate(employees):
    if i < 12:
        # New hire during Q1 2025
        emp['hire_date'] = (Q1_START + timedelta(days=random.randint(0, 89))).strftime('%Y-%m-%d')
        emp['status'] = 'active'
    elif i < 16:
        # Terminated during Q1 2025
        emp['hire_date'] = (datetime(2020, 1, 1) + timedelta(days=random.randint(0, 1460))).strftime('%Y-%m-%d')
        emp['termination_date'] = (Q1_START + timedelta(days=random.randint(5, 85))).strftime('%Y-%m-%d')
        emp['status'] = 'terminated'
    elif i < 39:
        # Terminated before Q1 2025
        emp['hire_date'] = (datetime(2018, 1, 1) + timedelta(days=random.randint(0, 1825))).strftime('%Y-%m-%d')
        emp['termination_date'] = (datetime(2023, 1, 1) + timedelta(days=random.randint(0, 700))).strftime('%Y-%m-%d')
        emp['status'] = 'terminated'
    else:
        # Regular active employee
        emp['hire_date'] = (datetime(2018, 1, 1) + timedelta(days=random.randint(0, 2200))).strftime('%Y-%m-%d')

# Re-sort by employee_id for clean output
employees.sort(key=lambda x: x['employee_id'])

# Write employees.csv
with open(os.path.join(DATA_DIR, 'employees.csv'), 'w', newline='') as f:
    fields = ['employee_id', 'first_name', 'last_name', 'email',
              'department_id', 'hire_date', 'termination_date', 'status', 'gender']
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(employees)

# ── Generate reviews (draft + final pairs) ──
# Employees with Q1 activity: active + terminated during Q1
reviewable = [e for e in employees
              if e['status'] == 'active' or
              (e['status'] == 'terminated' and e['termination_date'] >= '2025-01-01')]

reviews = []
rev_counter = 1
for emp in reviewable:
    final_score = round(random.uniform(1.5, 5.0), 1)
    draft_score = round(max(1.0, final_score - random.uniform(0.3, 0.8)), 1)

    # Draft review (January)
    reviews.append({
        'review_id': f'REV{rev_counter:04d}',
        'employee_id': emp['employee_id'],
        'quarter': '2025-Q1',
        'review_date': datetime(2025, 1, random.randint(10, 28)).strftime('%Y-%m-%d'),
        'score': draft_score,
        'reviewer_id': f'EMP{random.randint(1, 200):04d}',
        'status': 'draft',
    })
    rev_counter += 1

    # Final review (March)
    reviews.append({
        'review_id': f'REV{rev_counter:04d}',
        'employee_id': emp['employee_id'],
        'quarter': '2025-Q1',
        'review_date': datetime(2025, 3, random.randint(1, 25)).strftime('%Y-%m-%d'),
        'score': final_score,
        'reviewer_id': f'EMP{random.randint(1, 200):04d}',
        'status': 'final',
    })
    rev_counter += 1

# Sort by review_date ascending (drafts generally before finals)
reviews.sort(key=lambda x: x['review_date'])

with open(os.path.join(DATA_DIR, 'reviews.csv'), 'w', newline='') as f:
    fields = ['review_id', 'employee_id', 'quarter', 'review_date',
              'score', 'reviewer_id', 'status']
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(reviews)

# ── Generate compensation (European decimal format!) ──
comp_records = []
# Decide which employees get multiple records
emp_indices = list(range(200))
random.shuffle(emp_indices)
multi_2_set = set(emp_indices[:50])   # 50 employees -> 2 records
multi_3_set = set(emp_indices[50:60]) # 10 employees -> 3 records

for i, emp in enumerate(employees):
    dept_id = emp['department_id']
    lo, hi = SALARY_RANGES[dept_id]
    base_salary = round(random.uniform(lo, hi), 2)
    bonus = round(base_salary * random.uniform(0.05, 0.15), 2)

    hire_dt = datetime.strptime(emp['hire_date'], '%Y-%m-%d')
    first_effective = max(hire_dt + timedelta(days=30), datetime(2019, 1, 1))

    comp_records.append({
        'employee_id': emp['employee_id'],
        'effective_date': first_effective.strftime('%Y-%m-%d'),
        'base_salary': base_salary,
        'bonus': bonus,
        'currency': 'USD',
    })

    if i in multi_2_set or i in multi_3_set:
        new_salary = round(base_salary * random.uniform(1.03, 1.10), 2)
        new_bonus = round(new_salary * random.uniform(0.05, 0.15), 2)
        comp_records.append({
            'employee_id': emp['employee_id'],
            'effective_date': '2024-07-01',
            'base_salary': new_salary,
            'bonus': new_bonus,
            'currency': 'USD',
        })

    if i in multi_3_set:
        new_salary2 = round(base_salary * random.uniform(1.08, 1.18), 2)
        new_bonus2 = round(new_salary2 * random.uniform(0.05, 0.15), 2)
        comp_records.append({
            'employee_id': emp['employee_id'],
            'effective_date': '2025-01-15',
            'base_salary': new_salary2,
            'bonus': new_bonus2,
            'currency': 'USD',
        })

# Write compensation.csv with EUROPEAN DECIMAL FORMAT (comma as decimal separator)
# This is the trap: pd.read_csv() will read "95000,50" as a string, not a float.
with open(os.path.join(DATA_DIR, 'compensation.csv'), 'w') as f:
    f.write('employee_id,effective_date,base_salary,bonus,currency\n')
    for rec in comp_records:
        sal_str = f'{rec["base_salary"]:.2f}'.replace('.', ',')
        bonus_str = f'{rec["bonus"]:.2f}'.replace('.', ',')
        f.write(f'{rec["employee_id"]},{rec["effective_date"]},"{sal_str}","{bonus_str}",{rec["currency"]}\n')

# Write departments.csv
with open(os.path.join(DATA_DIR, 'departments.csv'), 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['department_id', 'name', 'budget'])
    writer.writeheader()
    for dept in DEPTS:
        writer.writerow({
            'department_id': dept['id'],
            'name': dept['name'],
            'budget': dept['budget'],
        })

# ── Compute expected output using CORRECT (bug-free) pipeline logic ──
emp_df = pd.read_csv(os.path.join(DATA_DIR, 'employees.csv'))
rev_df = pd.read_csv(os.path.join(DATA_DIR, 'reviews.csv'))
dept_df = pd.read_csv(os.path.join(DATA_DIR, 'departments.csv'))
comp_df = pd.read_csv(os.path.join(DATA_DIR, 'compensation.csv'), decimal=',')

# Correct: clean reviews keeping final (last by date)
rev_df['review_date'] = pd.to_datetime(rev_df['review_date'])
rev_clean = rev_df.sort_values('review_date').drop_duplicates(
    subset=['employee_id', 'quarter'], keep='last'
)

# Correct: deduplicate compensation (keep latest per employee)
comp_df['effective_date'] = pd.to_datetime(comp_df['effective_date'])
comp_dedup = comp_df.sort_values('effective_date').drop_duplicates(
    subset=['employee_id'], keep='last'
)

# Correct: build master dataset with no duplicates
master = pd.merge(
    emp_df,
    comp_dedup[['employee_id', 'base_salary', 'bonus']],
    on='employee_id', how='left'
)
avg_scores = rev_clean.groupby('employee_id')['score'].mean().reset_index()
avg_scores.columns = ['employee_id', 'avg_score']
master = pd.merge(master, avg_scores, on='employee_id', how='left')

# Correct: company summary with quarterly retention
active = master[master['status'] == 'active']
emp_df['hire_date'] = pd.to_datetime(emp_df['hire_date'])
emp_df['termination_date'] = pd.to_datetime(emp_df['termination_date'])

new_hires_count = int(len(emp_df[emp_df['hire_date'] >= '2025-01-01']))
q1_terms_count = int(len(emp_df[
    (emp_df['status'] == 'terminated') &
    (emp_df['termination_date'] >= '2025-01-01') &
    (emp_df['termination_date'] <= '2025-03-31')
]))
active_count = int(len(active))
total_headcount = int(len(master))

# Quarterly retention: employees present at start of Q1 who stayed
start_of_period = active_count + q1_terms_count - new_hires_count
retention_rate = round((1 - q1_terms_count / start_of_period) * 100, 1) if start_of_period > 0 else 100.0

company_summary = {
    'total_headcount': total_headcount,
    'active_employees': active_count,
    'new_hires': new_hires_count,
    'terminations_this_quarter': q1_terms_count,
    'retention_rate': retention_rate,
    'total_salary_budget': round(float(active['base_salary'].sum()), 2),
    'avg_salary': round(float(active['base_salary'].mean()), 2),
}

# Department metrics
dept_metrics = []
for _, dept in dept_df.iterrows():
    dept_data = master[master['department_id'] == dept['department_id']]
    dept_active = dept_data[dept_data['status'] == 'active']
    avg_sal = round(float(dept_active['base_salary'].mean()), 2) if len(dept_active) > 0 else 0.0
    avg_perf = round(float(dept_data['avg_score'].mean()), 2) if dept_data['avg_score'].notna().any() else 0.0
    dept_metrics.append({
        'department': dept['name'],
        'department_id': int(dept['department_id']),
        'headcount': int(len(dept_data)),
        'active_employees': int(len(dept_active)),
        'avg_salary': avg_sal,
        'avg_performance': avg_perf,
    })

# Performance summary
scores = master['avg_score'].dropna()
perf_summary = {
    'company_avg': round(float(scores.mean()), 2),
    'ratings_above_4': int((scores >= 4.0).sum()),
    'ratings_below_2': int((scores < 2.0).sum()),
}

# Write expected output
expected = {
    'quarter': '2025-Q1',
    'company_summary': company_summary,
    'department_metrics': dept_metrics,
    'performance_summary': perf_summary,
}

with open(os.path.join(EXPECTED_DIR, 'quarterly_report.json'), 'w') as f:
    json.dump(expected, f, indent=2)

print(f"Generated {len(employees)} employees, {len(reviews)} reviews, {len(comp_records)} compensation records")
print(f"Expected output: headcount={total_headcount}, active={active_count}, retention={retention_rate}%")
print(f"Salary budget: {company_summary['total_salary_budget']}, avg: {company_summary['avg_salary']}")
PYGEN

sudo -u ga python3 /tmp/generate_hr_data.py
rm -f /tmp/generate_hr_data.py

# ──────────────────────────────────────────────────────────
# 2. Create config.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.environ.get('HR_DATA_DIR', os.path.join(BASE_DIR, 'data'))
OUTPUT_DIR = os.environ.get('HR_OUTPUT_DIR', os.path.join(BASE_DIR, 'output'))

QUARTER = '2025-Q1'
QUARTER_START = '2025-01-01'
QUARTER_END = '2025-03-31'
EOF

# ──────────────────────────────────────────────────────────
# 3. Create pipeline modules (with bugs)
# ──────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/pipeline/__init__.py" << 'EOF'
EOF

# ── loader.py (BUG 1: no decimal=',' for European CSV format) ──
cat > "$WORKSPACE_DIR/pipeline/loader.py" << 'EOF'
import pandas as pd
import os
from config import DATA_DIR


def load_all_data():
    """Load all source data files."""
    return {
        'employees': pd.read_csv(os.path.join(DATA_DIR, 'employees.csv')),
        'reviews': pd.read_csv(os.path.join(DATA_DIR, 'reviews.csv')),
        'compensation': _load_compensation(),
        'departments': pd.read_csv(os.path.join(DATA_DIR, 'departments.csv')),
    }


def _load_compensation():
    """Load compensation records and ensure numeric types."""
    path = os.path.join(DATA_DIR, 'compensation.csv')
    df = pd.read_csv(path)
    df['base_salary'] = pd.to_numeric(df['base_salary'], errors='coerce')
    df['bonus'] = pd.to_numeric(df['bonus'], errors='coerce')
    return df
EOF

# ── cleaner.py (BUG 2: keep='first' keeps draft reviews, not final) ──
cat > "$WORKSPACE_DIR/pipeline/cleaner.py" << 'EOF'
import pandas as pd


def clean_employees(df):
    """Parse date columns in employee data."""
    df = df.copy()
    df['hire_date'] = pd.to_datetime(df['hire_date'])
    df['termination_date'] = pd.to_datetime(df['termination_date'], errors='coerce')
    return df


def clean_reviews(df):
    """Deduplicate reviews: keep one per employee per quarter."""
    df = df.copy()
    df['review_date'] = pd.to_datetime(df['review_date'])
    df = df.sort_values('review_date')
    df = df.drop_duplicates(subset=['employee_id', 'quarter'], keep='first')
    return df


def clean_compensation(df):
    """Parse date columns in compensation data."""
    df = df.copy()
    df['effective_date'] = pd.to_datetime(df['effective_date'], errors='coerce')
    return df
EOF

# ── transformer.py (BUG 3: merge without dedup creates duplicate rows) ──
cat > "$WORKSPACE_DIR/pipeline/transformer.py" << 'EOF'
import pandas as pd


def build_master_dataset(employees, compensation, reviews):
    """Join employee, compensation, and review data into a unified dataset."""
    # Join compensation data
    dataset = pd.merge(
        employees,
        compensation[['employee_id', 'base_salary', 'bonus', 'effective_date']],
        on='employee_id',
        how='left'
    )

    # Compute average review score per employee
    avg_scores = reviews.groupby('employee_id')['score'].mean().reset_index()
    avg_scores.columns = ['employee_id', 'avg_score']

    # Join review scores
    dataset = pd.merge(dataset, avg_scores, on='employee_id', how='left')

    return dataset
EOF

# ── analyzer.py (BUG 4: retention uses all-time data, not quarterly) ──
cat > "$WORKSPACE_DIR/pipeline/analyzer.py" << 'EOF'
import pandas as pd
import numpy as np
from config import QUARTER_START, QUARTER_END


def calculate_retention_rate(dataset):
    """Calculate employee retention rate."""
    active = len(dataset[dataset['status'] == 'active'])
    total = len(dataset)
    if total == 0:
        return 0.0
    return round(active / total * 100, 1)


def calculate_company_summary(dataset):
    """Compute company-wide summary metrics."""
    active = dataset[dataset['status'] == 'active']
    qs = pd.to_datetime(QUARTER_START)

    new_hires = len(dataset[pd.to_datetime(dataset['hire_date']) >= qs])

    salary_budget = round(float(active['base_salary'].sum()), 2) if active['base_salary'].notna().any() else None
    avg_sal = round(float(active['base_salary'].mean()), 2) if active['base_salary'].notna().any() else None

    return {
        'total_headcount': int(len(dataset)),
        'active_employees': int(len(active)),
        'new_hires': int(new_hires),
        'retention_rate': calculate_retention_rate(dataset),
        'total_salary_budget': salary_budget,
        'avg_salary': avg_sal,
    }


def calculate_department_metrics(dataset, departments):
    """Compute per-department metrics."""
    results = []
    for _, dept in departments.iterrows():
        dept_data = dataset[dataset['department_id'] == dept['department_id']]
        dept_active = dept_data[dept_data['status'] == 'active']

        avg_sal = round(float(dept_active['base_salary'].mean()), 2) \
            if dept_active['base_salary'].notna().any() and len(dept_active) > 0 else 0.0
        avg_perf = round(float(dept_data['avg_score'].mean()), 2) \
            if dept_data['avg_score'].notna().any() else 0.0

        results.append({
            'department': dept['name'],
            'department_id': int(dept['department_id']),
            'headcount': int(len(dept_data)),
            'active_employees': int(len(dept_active)),
            'avg_salary': avg_sal,
            'avg_performance': avg_perf,
        })
    return results


def calculate_performance_summary(dataset):
    """Compute performance score distribution."""
    scores = dataset['avg_score'].dropna()
    if len(scores) == 0:
        return {'company_avg': 0.0, 'ratings_above_4': 0, 'ratings_below_2': 0}

    return {
        'company_avg': round(float(scores.mean()), 2),
        'ratings_above_4': int((scores >= 4.0).sum()),
        'ratings_below_2': int((scores < 2.0).sum()),
    }
EOF

# ── reporter.py (clean, no bugs) ──
cat > "$WORKSPACE_DIR/pipeline/reporter.py" << 'EOF'
import json


def generate_report(report_data, output_path):
    """Write the quarterly report as JSON."""
    with open(output_path, 'w') as f:
        json.dump(report_data, f, indent=2, default=str)
EOF

# ──────────────────────────────────────────────────────────
# 4. Create main.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
import os
import sys
import warnings

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
warnings.filterwarnings('ignore', category=FutureWarning)

from pipeline.loader import load_all_data
from pipeline.cleaner import clean_employees, clean_reviews, clean_compensation
from pipeline.transformer import build_master_dataset
from pipeline.analyzer import calculate_company_summary, calculate_department_metrics, calculate_performance_summary
from pipeline.reporter import generate_report
from config import OUTPUT_DIR


def main():
    print("=== HR Analytics Pipeline ===")

    print("Loading data...")
    data = load_all_data()
    print(f"  Employees: {len(data['employees'])} records")
    print(f"  Reviews: {len(data['reviews'])} records")
    print(f"  Compensation: {len(data['compensation'])} records")
    print(f"  Departments: {len(data['departments'])} records")

    print("Cleaning data...")
    employees = clean_employees(data['employees'])
    reviews = clean_reviews(data['reviews'])
    compensation = clean_compensation(data['compensation'])
    departments = data['departments']

    print("Transforming data...")
    master = build_master_dataset(employees, compensation, reviews)
    print(f"  Master dataset: {len(master)} rows")

    print("Analyzing...")
    company = calculate_company_summary(master)
    dept_metrics = calculate_department_metrics(master, departments)
    perf = calculate_performance_summary(master)

    print("Generating report...")
    report = {
        'quarter': '2025-Q1',
        'company_summary': company,
        'department_metrics': dept_metrics,
        'performance_summary': perf,
    }

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    output_path = os.path.join(OUTPUT_DIR, 'quarterly_report.json')
    generate_report(report, output_path)
    print(f"Report saved to {output_path}")

    # Print summary
    print("\n--- Company Summary ---")
    for k, v in company.items():
        print(f"  {k}: {v}")


if __name__ == '__main__':
    main()
EOF

# ──────────────────────────────────────────────────────────
# 5. Create tests
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
EOF

cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import os
import sys
import json
import subprocess

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from pipeline.loader import load_all_data
from pipeline.cleaner import clean_reviews, clean_employees, clean_compensation
from pipeline.transformer import build_master_dataset
from pipeline.analyzer import calculate_retention_rate


def test_salary_data_valid():
    """Compensation data should have valid numeric salary values, not NaN."""
    data = load_all_data()
    comp = data['compensation']
    nan_count = int(comp['base_salary'].isna().sum())
    total = len(comp)
    assert nan_count == 0, (
        f"Found {nan_count} NaN values in base_salary out of {total} records. "
        f"Check how compensation.csv is being loaded — inspect the raw CSV format."
    )


def test_no_duplicate_employees():
    """Transformed dataset should have exactly one row per employee."""
    data = load_all_data()
    emp = clean_employees(data['employees'])
    comp = clean_compensation(data['compensation'])
    rev = clean_reviews(data['reviews'])
    master = build_master_dataset(emp, comp, rev)
    n_unique = master['employee_id'].nunique()
    n_rows = len(master)
    assert n_rows == n_unique, (
        f"Master dataset has {n_rows} rows but only {n_unique} unique employees. "
        f"Check for one-to-many relationships in merge operations."
    )


def test_reviews_are_final():
    """After cleaning, only final reviews should remain."""
    data = load_all_data()
    cleaned = clean_reviews(data['reviews'])
    non_final = cleaned[cleaned['status'] != 'final']
    assert len(non_final) == 0, (
        f"Found {len(non_final)} non-final reviews after cleaning. "
        f"Only 'final' reviews should be kept per employee per quarter."
    )


def test_retention_rate_valid():
    """Quarterly retention rate should be above 90%."""
    data = load_all_data()
    emp = clean_employees(data['employees'])
    comp = clean_compensation(data['compensation'])
    rev = clean_reviews(data['reviews'])
    master = build_master_dataset(emp, comp, rev)
    rate = calculate_retention_rate(master)
    assert rate > 90.0, (
        f"Retention rate {rate}% is implausibly low for a single quarter. "
        f"The formula may be using all-time termination data instead of quarterly."
    )


def test_report_matches_expected():
    """Generated report should match expected output within tolerance."""
    project_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Run the pipeline
    subprocess.run(
        [sys.executable, 'main.py'],
        cwd=project_dir,
        capture_output=True, text=True, timeout=30
    )

    output_path = os.path.join(project_dir, 'output', 'quarterly_report.json')
    expected_path = os.path.join(project_dir, 'expected_output', 'quarterly_report.json')

    assert os.path.exists(output_path), "Pipeline did not generate output/quarterly_report.json"
    assert os.path.exists(expected_path), "Expected output file is missing"

    with open(output_path) as f:
        actual = json.load(f)
    with open(expected_path) as f:
        expected = json.load(f)

    errors = []
    for key in ['total_headcount', 'active_employees', 'retention_rate',
                'total_salary_budget', 'avg_salary']:
        exp_val = expected['company_summary'][key]
        act_val = actual['company_summary'].get(key)

        if exp_val is None and act_val is None:
            continue
        if act_val is None:
            errors.append(f"{key}: expected {exp_val}, got None")
            continue
        if isinstance(exp_val, (int, float)) and exp_val != 0:
            diff = abs(act_val - exp_val) / abs(exp_val)
            if diff >= 0.02:
                errors.append(f"{key}: expected {exp_val}, got {act_val} (diff {diff:.1%})")

    assert len(errors) == 0, "Report mismatches:\n" + "\n".join(errors)
EOF

# ──────────────────────────────────────────────────────────
# 6. Create README.md
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# HR Analytics Pipeline

Quarterly analytics pipeline that processes employee data and generates a report.

## Project Structure

```
hr_analytics/
├── main.py                 # Pipeline entry point
├── config.py               # Configuration (paths, quarter dates)
├── pipeline/
│   ├── loader.py           # Stage 1: Load CSV data
│   ├── cleaner.py          # Stage 2: Clean and deduplicate
│   ├── transformer.py      # Stage 3: Join datasets
│   ├── analyzer.py         # Stage 4: Calculate metrics
│   └── reporter.py         # Stage 5: Generate JSON report
├── data/                   # Source CSV files
├── output/                 # Generated report
├── expected_output/        # Correct expected report
└── tests/                  # Test suite
```

## Usage

Run the pipeline:
```
python3 main.py
```

Run tests:
```
python3 -m pytest tests/ -v
```

Compare output with expected:
```
diff output/quarterly_report.json expected_output/quarterly_report.json
```

## Data Sources

- `data/employees.csv` — Employee records (200 employees)
- `data/reviews.csv` — Performance review records
- `data/compensation.csv` — Compensation and salary data
- `data/departments.csv` — Department information
EOF

# ──────────────────────────────────────────────────────────
# 7. Set permissions
# ──────────────────────────────────────────────────────────
chown -R ga:ga "$WORKSPACE_DIR"

# ──────────────────────────────────────────────────────────
# 8. Launch VS Code
# ──────────────────────────────────────────────────────────
echo "Starting VS Code..."
pkill -f "code" 2>/dev/null || true
sleep 2

sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR"

# Wait for VS Code to open
wait_for_window "Visual Studio Code" 30

focus_vscode_window
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

sleep 2
take_screenshot /tmp/task_initial.png

echo "=== HR Analytics Pipeline Task Setup Complete ==="
