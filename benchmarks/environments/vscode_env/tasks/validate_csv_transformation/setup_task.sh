#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up CSV Transformation Validation Task ==="

WORKSPACE_DIR="/home/ga/workspace/data_validation"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the transformation script
cat > "$WORKSPACE_DIR/parse_orders.py" << 'EOFSCRIPT'
#!/usr/bin/env python3
"""
Order data transformation script
Converts raw CSV exports to normalized format
"""
import csv
import sys
from datetime import datetime

def parse_date(date_str):
    """Parse various date formats"""
    formats = ['%Y-%m-%d', '%m/%d/%Y', '%d-%m-%Y']
    for fmt in formats:
        try:
            return datetime.strptime(date_str.strip(), fmt).strftime('%Y-%m-%d')
        except ValueError:
            continue
    return date_str

def transform_row(row):
    """Transform a single order row"""
    return {
        'order_id': row.get('OrderID', '').strip(),
        'customer_name': row.get('CustomerName', '').strip().title(),
        'order_date': parse_date(row.get('OrderDate', '')),
        'amount': f"{float(row.get('Amount', 0)):.2f}",
        'status': row.get('Status', 'PENDING').upper()
    }

def main():
    if len(sys.argv) != 3:
        print("Usage: python parse_orders.py <input.csv> <output.csv>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    with open(input_file, 'r') as infile, open(output_file, 'w', newline='') as outfile:
        reader = csv.DictReader(infile)
        fieldnames = ['order_id', 'customer_name', 'order_date', 'amount', 'status']
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        
        writer.writeheader()
        for row in reader:
            writer.writerow(transform_row(row))
    
    print(f"Transformation complete: {output_file}")

if __name__ == '__main__':
    main()
EOFSCRIPT

chmod +x "$WORKSPACE_DIR/parse_orders.py"

# Create sample input CSV with edge cases
cat > "$WORKSPACE_DIR/sample_input.csv" << 'EOFINPUT'
OrderID,CustomerName,OrderDate,Amount,Status
1001,john doe,2024-01-15,129.99,completed
1002,JANE SMITH,01/16/2024,45.50,pending
1003,Bob O'Brien,15-01-2024,299.0,shipped
1004,Alice,2024-01-17,89.99,completed
EOFINPUT

# Create expected output CSV
cat > "$WORKSPACE_DIR/expected_output.csv" << 'EOFEXPECTED'
order_id,customer_name,order_date,amount,status
1001,John Doe,2024-01-15,129.99,COMPLETED
1002,Jane Smith,2024-01-16,45.50,PENDING
1003,Bob O'Brien,2024-01-15,299.00,SHIPPED
1004,Alice,2024-01-17,89.99,COMPLETED
EOFEXPECTED

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== CSV Transformation Validation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open integrated terminal (Ctrl+\`)"
echo "  2. Run: python parse_orders.py sample_input.csv actual_output.csv"
echo "  3. Right-click actual_output.csv → 'Select for Compare'"
echo "  4. Right-click expected_output.csv → 'Compare with Selected'"
echo "  5. Verify files match"
echo "  6. Create validation_passed.txt with text: 'Output matches expected result'"
echo ""
echo "Workspace: $WORKSPACE_DIR"