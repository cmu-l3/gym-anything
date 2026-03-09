#!/bin/bash
set -e

echo "=== Setting up PII Masking Regex Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create directories
sudo -u ga mkdir -p /home/ga/Documents
mkdir -p /var/lib/task_data

# Generate synthetic data with Python
# We generate both the ODT file and a hidden JSON ground truth file
echo "Generating synthetic employee roster..."
python3 << 'PYEOF'
import random
import json
import os
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, TableColumnProperties
from odf.text import P, H
from odf.table import Table, TableColumn, TableRow, TableCell

# Setup ODT
doc = OpenDocumentText()

# Create styles
h1style = Style(name="Heading 1", family="paragraph")
h1style.addElement(TextProperties(attributes={'fontsize':"24pt", 'fontweight':"bold"}))
doc.styles.addElement(h1style)

# Add Title
h = H(outlinelevel=1, stylename=h1style, text="Employee Roster - CONFIDENTIAL")
doc.text.addElement(h)
doc.text.addElement(P(text="Warning: This document contains Personally Identifiable Information (PII)."))
doc.text.addElement(P(text=""))

# Setup Table
table = Table(name="Roster")
table.addElement(TableColumn(numbercolumnsrepeated=5))

# Header Row
tr = TableRow()
headers = ["ID", "Name", "SSN", "Email", "Department"]
for header in headers:
    tc = TableCell()
    tc.addElement(P(text=header))
    tr.addElement(tc)
table.addElement(tr)

# Data Generation Helpers
first_names = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin"]
domains = ["legacy-systems.net", "corp-mail.org", "enterprise.com", "internal.io", "web-services.co.uk"]
depts = ["Sales", "Engineering", "HR", "Legal", "Marketing", "Finance", "Support"]

ground_truth = []

# Generate 50 records
for i in range(1, 51):
    emp_id = f"E{1000+i}"
    fn = random.choice(first_names)
    ln = random.choice(last_names)
    name = f"{fn} {ln}"
    
    # Generate SSN
    area = random.randint(100, 899)
    group = random.randint(10, 99)
    serial = random.randint(1000, 9999)
    ssn = f"{area}-{group}-{serial}"
    
    # Generate Email
    username = f"{fn.lower()}.{ln.lower()}"
    domain = random.choice(domains)
    email = f"{username}@{domain}"
    
    dept = random.choice(depts)
    
    # Add to ODT
    tr = TableRow()
    cells = [emp_id, name, ssn, email, dept]
    for val in cells:
        tc = TableCell()
        tc.addElement(P(text=val))
        tr.addElement(tc)
    table.addElement(tr)
    
    # Add to ground truth
    ground_truth.append({
        "id": emp_id,
        "original_ssn": ssn,
        "last_4": str(serial),
        "username": username,
        "original_email": email
    })

doc.text.addElement(table)

# Save ODT
doc.save("/home/ga/Documents/employee_roster_sensitive.odt")

# Save Ground Truth
with open("/var/lib/task_data/roster_ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2)

print("Data generation complete.")
PYEOF

# Set permissions
chown ga:ga /home/ga/Documents/employee_roster_sensitive.odt
chmod 666 /home/ga/Documents/employee_roster_sensitive.odt
# Ground truth remains root-owned so agent cannot see it

# Launch LibreOffice Writer
echo "Launching LibreOffice Writer..."
su - ga -c "DISPLAY=:1 libreoffice --writer --norestore /home/ga/Documents/employee_roster_sensitive.odt > /tmp/writer.log 2>&1 &"

# Wait for process and window
wait_for_process "soffice" 20
wait_for_window "employee_roster_sensitive" 60 || wait_for_window "LibreOffice Writer" 60

# Maximize and focus
wid=$(get_writer_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
    
    # Dismiss "Tip of the Day" if it appears
    sleep 2
    safe_xdotool ga :1 key Escape 2>/dev/null || true
fi

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="