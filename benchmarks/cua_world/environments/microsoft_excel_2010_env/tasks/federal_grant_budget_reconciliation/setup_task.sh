#!/bin/bash
set -e
echo "=== Setting up Federal Grant Budget Reconciliation Task ==="

# 1. Define paths
TASK_DIR="/workspace/tasks/federal_grant_budget_reconciliation"
DOCS_DIR="/home/ga/Documents"
DATA_FILE="$DOCS_DIR/nsf_grant_ledger.xlsx"
mkdir -p "$DOCS_DIR"

# 2. Generate the Excel file using Python
# We generate it on the fly to ensure we know the ground truth values
echo "Generating grant data..."
cat > /tmp/generate_data.py << 'EOF'
import pandas as pd
import numpy as np
import random
from datetime import datetime, timedelta

# Set seed for reproducibility
random.seed(42)
np.random.seed(42)

# --- Configuration ---
FA_RATE = 0.53
BUDGET_CATEGORIES = {
    'Salaries & Wages': 150000,
    'Fringe Benefits': 45000,
    'Tuition Remission': 30000,
    'Materials & Supplies': 25000,
    'Travel': 15000,
    'Equipment': 20000,
    'Participant Support': 10000,
    'Consultant Services': 5000,
    'Indirect Costs (F&A)': 159000  # Approx estimate
}

# Object Code Map
# Code: (Category, MTDC_Inclusion)
OBJ_CODES = {
    1010: ('Salaries & Wages', 'Yes'),
    1020: ('Salaries & Wages', 'Yes'),
    1030: ('Salaries & Wages', 'Yes'),
    1200: ('Fringe Benefits', 'Yes'),
    1500: ('Tuition Remission', 'No'),    # EXCLUDED
    2010: ('Materials & Supplies', 'Yes'),
    2020: ('Materials & Supplies', 'Yes'),
    3010: ('Travel', 'Yes'),
    3020: ('Travel', 'Yes'),
    4010: ('Equipment', 'No'),           # EXCLUDED (>5k)
    5010: ('Participant Support', 'No'), # EXCLUDED
    6010: ('Consultant Services', 'Yes')
}

# --- Generate Ledger ---
data = []
start_date = datetime(2023, 1, 1)

# Generate ~150 transactions
for i in range(150):
    date = start_date + timedelta(days=random.randint(0, 300))
    code = random.choice(list(OBJ_CODES.keys()))
    category, mtdc = OBJ_CODES[code]
    
    # Amount logic based on category to make it realistic
    if category == 'Salaries & Wages':
        desc = random.choice(['Postdoc Salary', 'Grad Student Salary', 'PI Summer Salary'])
        amount = round(random.uniform(2000, 8000), 2)
    elif category == 'Tuition Remission':
        desc = 'Spring 2023 Tuition'
        amount = 12000.00
    elif category == 'Equipment':
        desc = 'Microscope System'
        amount = round(random.uniform(5001, 15000), 2) # >5k
    elif category == 'Materials & Supplies':
        desc = random.choice(['Lab Flasks', 'Chemical Reagents', 'Pipette Tips'])
        amount = round(random.uniform(50, 1500), 2)
    elif category == 'Travel':
        desc = 'Conference Flight/Hotel'
        amount = round(random.uniform(500, 2500), 2)
    elif category == 'Participant Support':
        desc = 'Workshop Stipend'
        amount = 500.00
    else:
        desc = 'Consulting Fee'
        amount = round(random.uniform(1000, 4000), 2)

    data.append([date, f"Vendor_{random.randint(100,999)}", desc, code, amount])

ledger_df = pd.DataFrame(data, columns=['Date', 'Vendor', 'Description', 'Object_Code', 'Amount'])
ledger_df['Date'] = ledger_df['Date'].dt.date

# --- Generate Object Codes Sheet ---
obj_df = pd.DataFrame([
    {'Object_Code': k, 'Budget_Category': v[0], 'MTDC_Inclusion': v[1]} 
    for k, v in OBJ_CODES.items()
])

# --- Generate Report Sheet (Template) ---
report_rows = []
for cat, budget in BUDGET_CATEGORIES.items():
    if cat == 'Indirect Costs (F&A)':
        continue
    report_rows.append({'Budget_Category': cat, 'Budgeted_Amount': budget, 'Direct_Costs_Expended': None, 'FA_Costs_Expended': None, 'Total_Costs': None, 'Remaining_Balance': None})

# Add F&A row separate logic in valid excel usually, but for this table we list it
# Actually, standard NSF forms group Direct vs Indirect. 
# We'll make a simple table: Category | Budget | Direct Expended | F&A Expended | Total | Remaining
report_df = pd.DataFrame(report_rows)

# Create Excel Writer
path = "/home/ga/Documents/nsf_grant_ledger.xlsx"
writer = pd.ExcelWriter(path, engine='xlsxwriter')

ledger_df.to_excel(writer, sheet_name='General_Ledger', index=False)
obj_df.to_excel(writer, sheet_name='Object_Codes', index=False)
report_df.to_excel(writer, sheet_name='Financial_Report', index=False, startrow=5)

# Add some headers/formatting to Report Sheet
workbook = writer.book
worksheet = writer.sheets['Financial_Report']
bold = workbook.add_format({'bold': True, 'font_size': 14})
worksheet.write('A1', 'NSF GRANT FINANCIAL RECONCILIATION REPORT', bold)
worksheet.write('A3', 'F&A Rate:', workbook.add_format({'bold': True}))
worksheet.write('B3', 0.53)
worksheet.write('A4', 'MTDC Base:', workbook.add_format({'bold': True}))
worksheet.write('B4', 'Excludes Equipment, Tuition, Participant Support')

# Add TOTALS row logic (just text, agent must fill formulas)
row_idx = 5 + len(report_rows) + 1
worksheet.write(f'A{row_idx}', 'TOTAL PROJECT')

writer.close()
print(f"Created {path}")

# --- Calculate Ground Truth for verification later ---
# We calculate the totals
def calc_fa(row):
    cat, mtdc_inc = OBJ_CODES[row['Object_Code']]
    if mtdc_inc == 'Yes':
        return row['Amount'] * FA_RATE
    return 0.0

ledger_df['Calculated_FA'] = ledger_df.apply(calc_fa, axis=1)
total_direct = ledger_df['Amount'].sum()
total_fa = ledger_df['Calculated_FA'].sum()
print(f"Ground Truth - Direct: {total_direct}, F&A: {total_fa}")

# Save ground truth to hidden file
with open("/tmp/ground_truth_values.txt", "w") as f:
    f.write(f"{total_direct},{total_fa}")
EOF

python3 /tmp/generate_data.py

# 3. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 4. Start Excel
echo "Starting Excel..."
# Assuming standard environment path, adjust if needed for specific docker container
if ! pgrep -f "EXCEL.EXE" > /dev/null; then
    su - ga -c "DISPLAY=:1 wine 'C:\\Program Files\\Microsoft Office\\Office14\\EXCEL.EXE' 'Z:${DATA_FILE}' &"
fi

# 5. Wait for window and maximize
echo "Waiting for Excel to load..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Excel"; then
        echo "Excel window found."
        sleep 2
        # Maximize
        DISPLAY=:1 wmctrl -r "Excel" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        # Focus
        DISPLAY=:1 wmctrl -a "Excel" 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Initial Screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="