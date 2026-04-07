#!/bin/bash
# Setup script for Data Cleansing Regex task
# Generates a messy dataset 'ACQUIRED_EMPLOYEES' with controlled corruption patterns

set -e

echo "=== Setting up Data Cleansing Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Generate Messy Data SQL ---
echo "[2/4] Generating messy data..."

python3 << 'PYEOF'
import random
import datetime

# Data pools
first_names = ["John", "Jane", "Robert", "Emily", "Michael", "Sarah", "David", "Jessica", "James", "Mary", "María-José", "Jean-Luc"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "O'Connor", "Van Dyck"]
depts = ["IT", "Human Resources", "Finance", "Marketing", "Sales", "Operations", "Legal", "R&D"]
jobs = ["Software Engineer", "Manager", "Analyst", "Director", "Vice President", "Assistant", "Developer", "Accountant"]

def mess_up_id(nid):
    styles = [
        f"EMP-{nid:04d}", f"E{nid:04d}", f"#{nid}", f"  {nid}  ", f"No. {nid}", f"{nid}"
    ]
    return random.choice(styles)

def mess_up_name(first, last):
    style = random.choice([1, 2, 3, 4, 5])
    if style == 1: return f"  {first.upper()}   {last.upper()}  "
    if style == 2: return f"{first.lower()} {last.lower()}"
    if style == 3: return f"{first}  {last}"
    if style == 4: return f"{first} {last}" # Clean
    return f"  {first} {last}  "

def mess_up_email(first, last, company="acme.com"):
    base = f"{first}.{last}@{company}"
    style = random.choice([1, 2, 3, 4, 5, 6])
    if style == 1: return base.upper()
    if style == 2: return f" {base} "
    if style == 3: return f"{first}{last}" # Missing @
    if style == 4: return f"{first}@{company}" # Missing last
    if style == 5: return base.replace("@", " @ ")
    return base

def mess_up_phone():
    # Target: 555-123-4567
    a, b, c = random.randint(100,999), random.randint(100,999), random.randint(1000,9999)
    style = random.choice([1, 2, 3, 4, 5, 6])
    if style == 1: return f"({a}) {b}-{c}"
    if style == 2: return f"{a}.{b}.{c}"
    if style == 3: return f"+1-{a}-{b}-{c}"
    if style == 4: return f"{a}{b}{c}"
    if style == 5: return f"1-{a}-{b}-{c}"
    return f"{a}-{b}-{c}"

def mess_up_salary():
    val = random.randint(40, 150) * 1000
    style = random.choice([1, 2, 3, 4, 5])
    if style == 1: return f"${val:,}"
    if style == 2: return f"USD {val}.00"
    if style == 3: return f"{val}"
    if style == 4: return f"  {val} "
    if style == 5: return f"${val}"
    return str(val)

def mess_up_date():
    dt = datetime.date(2015, 1, 1) + datetime.timedelta(days=random.randint(0, 3000))
    style = random.choice([1, 2, 3, 4, 5])
    if style == 1: return dt.strftime("%Y-%m-%d")
    if style == 2: return dt.strftime("%m/%d/%Y")
    if style == 3: return dt.strftime("%d-%b-%Y").upper()
    if style == 4: return dt.strftime("%B %d, %Y")
    if style == 5: return dt.strftime("%Y/%m/%d")
    return dt.strftime("%Y-%m-%d")

def mess_up_job(job):
    # Sr., Mgr, etc.
    replacements = {
        "Senior": ["Sr.", "Sr", "SENIOR"],
        "Junior": ["Jr.", "Jr"],
        "Manager": ["Mgr", "Mgr.", "MANAGER"],
        "Engineer": ["Engr", "Engr."],
        "Assistant": ["Asst", "Asst."],
        "Director": ["Dir", "Dir."],
        "Vice President": ["VP", "V.P."],
        "Department": ["Dept", "Dept."],
        "Marketing": ["Mktg"]
    }
    
    # Add prefix
    prefix = random.choice(["", "Senior ", "Junior "])
    full_job = prefix + job
    
    words = full_job.split()
    new_words = []
    for w in words:
        if w in replacements:
            new_words.append(random.choice(replacements[w]))
        elif w in ["Senior", "Junior"] and random.random() > 0.5:
             new_words.append(random.choice(replacements[w]))
        else:
            if random.random() > 0.7:
                new_words.append(w.upper())
            else:
                new_words.append(w)
    return " ".join(new_words)

def mess_up_dept(dept):
    replacements = {
        "IT": ["I.T.", "Info Tech", "Information Technology"],
        "Human Resources": ["HR", "H.R.", "HUMAN RESOURCES"],
        "Finance": ["Fin", "Fin.", "FINANCE"],
        "Marketing": ["Mktg", "MARKETING"],
        "Operations": ["Ops", "OPERATIONS"],
        "Legal": ["LEGAL"],
        "R&D": ["Research", "Research and Development"]
    }
    if dept in replacements and random.random() > 0.3:
        return random.choice(replacements[dept])
    if random.random() > 0.7:
        return dept.upper()
    if random.random() > 0.8:
        return f"  {dept} "
    return dept

# Generate SQL
sql = """
SET DEFINE OFF;
DROP TABLE acquired_employees CASCADE CONSTRAINTS;
DROP TABLE clean_employees CASCADE CONSTRAINTS;

CREATE TABLE acquired_employees (
    emp_num VARCHAR2(50),
    full_name VARCHAR2(200),
    email_addr VARCHAR2(200),
    phone VARCHAR2(100),
    salary_text VARCHAR2(100),
    hire_date_text VARCHAR2(100),
    job_title_raw VARCHAR2(200),
    dept_name_raw VARCHAR2(200)
);
"""

# Hardcode a few known edge cases for verifier spot checks
# ID 42: John Doe
# ID 88: Jane Smith
# ID 99: Bob (no email domain)

rows = []
# Ensure unique numeric IDs
used_ids = set([42, 88, 99])

# Row 42
rows.append(f"INSERT INTO acquired_employees VALUES ('EMP-0042', '  john   DOE  ', 'JOHN.DOE @acme.com', '(555) 123-4567', '$75,000', '2019-03-15', 'Sr. Software Engr.', '  IT ');")

# Row 88
rows.append(f"INSERT INTO acquired_employees VALUES ('#88', 'JANE SMITH', 'jane@ ACME.COM ', '555.123.4567', 'USD 92500.00', '03/15/2019', 'Mgr, Operations', 'Ops');")

# Row 99
rows.append(f"INSERT INTO acquired_employees VALUES ('99', 'Bob Jones', 'bob', '+1-555-999-9999', '60000', '15-MAR-2020', 'Sales Rep', 'Sales');")

# Generate remaining 42 rows
for i in range(1, 43):
    nid = i
    while nid in used_ids:
        nid += 100
    used_ids.add(nid)
    
    fname = random.choice(first_names)
    lname = random.choice(last_names)
    job = random.choice(jobs)
    dept = random.choice(depts)
    
    v_id = mess_up_id(nid)
    v_name = mess_up_name(fname, lname)
    v_email = mess_up_email(fname, lname)
    v_phone = mess_up_phone()
    v_sal = mess_up_salary()
    v_date = mess_up_date()
    v_job = mess_up_job(job)
    v_dept = mess_up_dept(dept)
    
    rows.append(f"INSERT INTO acquired_employees VALUES ('{v_id}', '{v_name}', '{v_email}', '{v_phone}', '{v_sal}', '{v_date}', '{v_job}', '{v_dept}');")

sql += "\n".join(rows)
sql += "\nCOMMIT;\nEXIT;\n"

with open("/tmp/populate_messy.sql", "w") as f:
    f.write(sql)
PYEOF

# --- Execute SQL ---
echo "[3/4] Populating database..."
oracle_query_raw "@'/tmp/populate_messy.sql'" "hr" > /dev/null 2>&1

# --- Record Initial State ---
echo "[4/4] Recording state..."
date +%s > /tmp/task_start_timestamp

# Verify rows loaded
COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM acquired_employees;" "hr" | tr -d ' ')
echo "Loaded $COUNT rows into ACQUIRED_EMPLOYEES"

if [ "$COUNT" -ne 45 ]; then
    echo "ERROR: Expected 45 rows, got $COUNT"
    exit 1
fi

# Ensure CLEAN_EMPLOYEES is gone
oracle_query "DROP TABLE clean_employees CASCADE CONSTRAINTS;" "hr" > /dev/null 2>&1 || true

# Remove any old report
rm -f /home/ga/Desktop/data_cleansing_report.txt

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="