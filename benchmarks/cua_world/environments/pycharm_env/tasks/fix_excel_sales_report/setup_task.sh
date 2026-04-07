#!/bin/bash
echo "=== Setting up Fix Excel Sales Report Task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/sales_reporting"
DATA_DIR="$PROJECT_DIR/data"

# 1. Clean previous run
rm -rf "$PROJECT_DIR"
mkdir -p "$DATA_DIR"

# 2. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pandas
openpyxl
EOF

# 3. Generate Real Data (CSV) using Python
# We generate enough data to exceed the hardcoded limit of 100 rows in the bug
python3 -c '
import csv
import random
from datetime import datetime, timedelta

products = [
    ("Laptop", 1200.00), ("Mouse", 25.00), ("Keyboard", 75.00),
    ("Monitor", 300.00), ("HDMI Cable", 15.00), ("Headset", 150.00),
    ("Webcam", 80.00), ("Docking Station", 200.00)
]

start_date = datetime(2023, 1, 1)
rows = []

# Generate 150 transactions
for i in range(150):
    txn_id = 5000 + i
    prod, price = random.choice(products)
    
    # Random date (European format in CSV)
    dt = start_date + timedelta(days=random.randint(0, 30))
    # Pick dates that are ambiguous (e.g. 02/05) and unambiguous (15/05)
    if i % 5 == 0:
        dt = start_date + timedelta(days=14) # 15th of Jan
    
    date_str = dt.strftime("%d/%m/%Y %H:%M")
    
    # 10% chance of return (negative quantity)
    if random.random() < 0.1:
        qty = -1 * random.randint(1, 3)
        invoice = f"C{txn_id}"
    else:
        qty = random.randint(1, 10)
        invoice = str(txn_id)
        
    rows.append([invoice, prod, qty, date_str, price, 12345, "United Kingdom"])

with open("'"$DATA_DIR"'/transactions.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["InvoiceNo", "Description", "Quantity", "InvoiceDate", "UnitPrice", "CustomerID", "Country"])
    writer.writerows(rows)
'

# 4. Create the Buggy Python Script
cat > "$PROJECT_DIR/generate_report.py" << 'PYEOF'
import pandas as pd
from openpyxl import load_workbook
from openpyxl.styles import PatternFill
from openpyxl.formatting.rule import CellIsRule

def generate_report():
    input_file = 'data/transactions.csv'
    output_file = 'weekly_sales_report.xlsx'

    print(f"Reading data from {input_file}...")
    
    # BUG 1: Date Parsing Error
    # Pandas default or US format specification will fail/misinterpret DD/MM/YYYY
    # We force a US format to ensure it breaks on >12th days and misinterprets others
    try:
        df = pd.read_csv(input_file)
        # Attempting to parse with wrong format
        df['InvoiceDate'] = pd.to_datetime(df['InvoiceDate'], format='%m/%d/%Y %H:%M')
    except Exception:
        # Fallback that might still be wrong or leave as object
        print("Warning: Date parsing with specific format failed, trying default...")
        df = pd.read_csv(input_file)
        # If we leave it as string, it's also a bug for Excel analysis
    
    print("Calculating metrics...")
    
    # BUG 2: Incorrect Revenue Logic (Treats returns as positive revenue)
    # Returns have negative quantity, but here we take absolute value
    df['TotalRevenue'] = df['Quantity'].abs() * df['UnitPrice']
    
    # Save to Excel
    print(f"Saving to {output_file}...")
    df.to_excel(output_file, index=False, sheet_name='Sales')
    
    # Open with openpyxl for formatting
    wb = load_workbook(output_file)
    ws = wb['Sales']
    
    last_row = ws.max_row
    
    # BUG 3: Static Formula Range
    # Hardcoded to 100, but data might be larger
    ws[f'F{last_row + 2}'] = "Average Revenue:"
    ws[f'G{last_row + 2}'] = "=AVERAGE(G2:G100)"
    
    # BUG 4: Inverted Conditional Formatting
    # Supposed to highlight High Value (> 500) in Green
    # Currently highlighting Low Value (< 500) in Green
    green_fill = PatternFill(start_color='00FF00', end_color='00FF00', fill_type='solid')
    
    # Applying to Revenue column (G)
    # "lessThan" 500 is wrong, should be "greaterThan"
    rule = CellIsRule(operator='lessThan', formula=['500'], stopIfTrue=True, fill=green_fill)
    
    ws.conditional_formatting.add(f'G2:G{last_row}', rule)
    
    wb.save(output_file)
    print("Report generated successfully.")

if __name__ == "__main__":
    generate_report()
PYEOF

# 5. Open PyCharm Project
echo "Opening PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "sales_reporting"

# 6. Initial Screenshot
take_screenshot /tmp/task_start.png

# 7. Record Start Time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="