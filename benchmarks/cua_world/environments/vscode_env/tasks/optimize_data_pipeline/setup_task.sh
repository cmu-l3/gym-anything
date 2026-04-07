#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Optimize Data Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/sales_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
sudo mkdir -p "/var/lib/pipeline_ground_truth"
sudo chown -R ga:ga "/var/lib/pipeline_ground_truth"

cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Generate Realistic Retail Data (Domain-Specific Generator)
# ─────────────────────────────────────────────────────────────
echo "Generating realistic retail transaction data..."

python3 << 'PYDATA' > "$WORKSPACE_DIR/data/generate_data.py"
import csv
import random
import datetime

random.seed(42)

DEPARTMENTS = ['Electronics', 'Home', 'Apparel', 'Toys', 'Sports']
COUNTRIES = ['UK', 'Germany', 'France', 'Spain', 'USA']

def generate_transactions(filename, num_rows):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['InvoiceNo', 'StockCode', 'Description', 'Quantity', 'InvoiceDate', 'UnitPrice', 'CustomerID', 'Country', 'Department'])
        
        start_date = datetime.datetime(2023, 1, 1)
        
        for i in range(num_rows):
            invoice = f"{random.randint(500000, 599999)}"
            stock = f"{random.randint(10000, 99999)}{random.choice(['A', 'B', 'C', ''])}"
            desc = f"PRODUCT {stock}"
            qty = int(random.paretovariate(1.5) * 5) + 1
            if qty > 100: qty = random.randint(1, 100)
            
            date = start_date + datetime.timedelta(minutes=random.randint(0, 500000))
            price = round(random.lognormvariate(2.0, 1.0), 2)
            cust = f"{random.randint(12000, 18000)}"
            country = random.choices(COUNTRIES, weights=[0.6, 0.1, 0.1, 0.1, 0.1])[0]
            dept = random.choice(DEPARTMENTS)
            
            writer.writerow([invoice, stock, desc, qty, date.strftime('%Y-%m-%d %H:%M:%S'), price, cust, country, dept])

def generate_returns(filename, num_rows):
    with open(filename, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['ReturnID', 'OriginalInvoice', 'ReturnDate', 'Reason'])
        for i in range(num_rows):
            ret_id = f"R{random.randint(10000, 99999)}"
            orig_inv = f"{random.randint(500000, 599999)}"
            date = datetime.datetime(2023, 6, 1) + datetime.timedelta(days=random.randint(0, 180))
            reason = random.choice(['Defective', 'Changed Mind', 'Wrong Item'])
            writer.writerow([ret_id, orig_inv, date.strftime('%Y-%m-%d'), reason])

# Generate a dataset large enough to show performance issues but small enough to complete in <30s
generate_transactions("data/transactions.csv", 15000)
generate_returns("data/returns.csv", 500)
PYDATA

sudo -u ga python3 "$WORKSPACE_DIR/data/generate_data.py"

# ─────────────────────────────────────────────────────────────
# 2. Create the Pipeline Source Files
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/config.py" << 'EOF'
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(BASE_DIR, 'data')
OUTPUT_DIR = os.path.join(BASE_DIR, 'output')

TRANSACTIONS_FILE = os.path.join(DATA_DIR, 'transactions.csv')
RETURNS_FILE = os.path.join(DATA_DIR, 'returns.csv')
EOF

cat > "$WORKSPACE_DIR/pipeline/data_loader.py" << 'EOF'
import pandas as pd

def load_department_data(csv_path, departments):
    """Load transactions and filter for specific departments."""
    # PERFORMANCE NOTE: B1 - Redundant I/O operations
    # Reading the file multiple times from disk is extremely slow.
    results = {}
    for dept in departments:
        df = pd.read_csv(csv_path)
        results[dept] = df[df['Department'] == dept]
    
    if results:
        return pd.concat(results.values())
    return pd.DataFrame()
EOF

cat > "$WORKSPACE_DIR/pipeline/sales_aggregator.py" << 'EOF'
import pandas as pd

def aggregate_sales(df):
    """Calculate total revenue and quantity per department."""
    # PERFORMANCE NOTE: B2 - Inefficient row iteration
    # iterrows() is very slow in pandas. Use vectorized groupby instead.
    results = {}
    for idx, row in df.iterrows():
        dept = row['Department']
        if dept not in results:
            results[dept] = {'total_revenue': 0.0, 'total_qty': 0}
            
        results[dept]['total_revenue'] += row['Quantity'] * row['UnitPrice']
        results[dept]['total_qty'] += row['Quantity']
        
    # Convert back to dataframe
    agg_df = pd.DataFrame.from_dict(results, orient='index')
    agg_df.index.name = 'Department'
    return agg_df.sort_index()
EOF

cat > "$WORKSPACE_DIR/pipeline/invoice_matcher.py" << 'EOF'
import pandas as pd

def match_returns(transactions_df, returns_df):
    """Find all transactions that have a matching return record."""
    # PERFORMANCE NOTE: B3 - O(n^2) nested loop comparison
    # Comparing every row to every other row is disastrous for performance.
    matched_invoices = []
    
    for _, inv_row in transactions_df.iterrows():
        is_returned = False
        for _, ret_row in returns_df.iterrows():
            if str(inv_row['InvoiceNo']) == str(ret_row['OriginalInvoice']):
                is_returned = True
                break
                
        if is_returned:
            matched_invoices.append(inv_row['InvoiceNo'])
            
    # Return dataframe of matched transactions
    return transactions_df[transactions_df['InvoiceNo'].isin(matched_invoices)]
EOF

cat > "$WORKSPACE_DIR/pipeline/report_builder.py" << 'EOF'
import pandas as pd

def build_text_report(agg_df):
    """Build a formatted text summary from the aggregated dataframe."""
    # PERFORMANCE NOTE: B4 - Inefficient string building
    # Using += for string concatenation in a loop creates many intermediate objects.
    
    report = "========================================\n"
    report += "       DEPARTMENT SALES SUMMARY         \n"
    report += "========================================\n\n"
    
    # Process 10,000 dummy lines to simulate a massive report body
    for i in range(10000):
        report += f"Processing record block {i}...\n"
        
    report += "\n--- FINAL TOTALS ---\n"
    for dept, row in agg_df.iterrows():
        rev = round(row['total_revenue'], 2)
        qty = int(row['total_qty'])
        report += f"DEPT: {dept.ljust(15)} | REV: ${rev:<10} | QTY: {qty}\n"
        
    report += "========================================\n"
    return report
EOF

cat > "$WORKSPACE_DIR/pipeline/trend_calculator.py" << 'EOF'
import pandas as pd

def calculate_cumulative_revenue(df):
    """Calculate the running cumulative revenue over time."""
    # PERFORMANCE NOTE: B5 - Manual cumulative calculation
    # Manually accumulating values in a loop defeats pandas vectorization.
    
    df = df.copy()
    df = df.sort_values('InvoiceDate').reset_index(drop=True)
    df['Revenue'] = df['Quantity'] * df['UnitPrice']
    
    cumulative = []
    current_sum = 0.0
    
    for idx, row in df.iterrows():
        current_sum += row['Revenue']
        cumulative.append(current_sum)
        
    df['Cumulative_Revenue'] = cumulative
    return df
EOF

cat > "$WORKSPACE_DIR/run_pipeline.py" << 'EOF'
import time
import os
import pandas as pd

import config
from pipeline.data_loader import load_department_data
from pipeline.sales_aggregator import aggregate_sales
from pipeline.invoice_matcher import match_returns
from pipeline.report_builder import build_text_report
from pipeline.trend_calculator import calculate_cumulative_revenue

def main():
    print("Starting data pipeline...")
    start_total = time.time()
    
    os.makedirs(config.OUTPUT_DIR, exist_ok=True)
    
    # 1. Load Data
    print("1. Loading department data...")
    t0 = time.time()
    depts = ['Electronics', 'Home', 'Apparel', 'Toys', 'Sports']
    df = load_department_data(config.TRANSACTIONS_FILE, depts)
    print(f"   -> Completed in {time.time() - t0:.2f} seconds. Loaded {len(df)} rows.")
    
    # 2. Aggregate Sales
    print("2. Aggregating sales by department...")
    t0 = time.time()
    agg_df = aggregate_sales(df)
    agg_df.to_csv(os.path.join(config.OUTPUT_DIR, 'department_summary.csv'))
    print(f"   -> Completed in {time.time() - t0:.2f} seconds.")
    
    # 3. Match Returns
    print("3. Matching returns to invoices...")
    t0 = time.time()
    returns_df = pd.read_csv(config.RETURNS_FILE)
    matched_df = match_returns(df, returns_df)
    matched_df.to_csv(os.path.join(config.OUTPUT_DIR, 'matched_invoices.csv'), index=False)
    print(f"   -> Completed in {time.time() - t0:.2f} seconds. Found {len(matched_df)} matches.")
    
    # 4. Calculate Trends
    print("4. Calculating cumulative revenue trends...")
    t0 = time.time()
    trend_df = calculate_cumulative_revenue(df)
    trend_df[['InvoiceDate', 'Revenue', 'Cumulative_Revenue']].to_csv(os.path.join(config.OUTPUT_DIR, 'trends.csv'), index=False)
    print(f"   -> Completed in {time.time() - t0:.2f} seconds.")
    
    # 5. Build Report
    print("5. Building text report...")
    t0 = time.time()
    report = build_text_report(agg_df)
    with open(os.path.join(config.OUTPUT_DIR, 'sales_report.txt'), 'w') as f:
        f.write(report)
    print(f"   -> Completed in {time.time() - t0:.2f} seconds.")
    
    print(f"Pipeline finished successfully in {time.time() - start_total:.2f} seconds total.")

if __name__ == "__main__":
    main()
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 3. Generate Ground Truth (Run the slow pipeline once)
# ─────────────────────────────────────────────────────────────
echo "Running initial pipeline to generate ground truth outputs (this will take ~30 seconds)..."
sudo -u ga python3 "$WORKSPACE_DIR/run_pipeline.py" > /tmp/initial_pipeline_run.log 2>&1

# Copy outputs to ground truth directory
sudo cp "$WORKSPACE_DIR/output/"* "/var/lib/pipeline_ground_truth/"
sudo chown -R ga:ga "/var/lib/pipeline_ground_truth/"

# Clear the output directory for the agent
sudo -u ga rm -f "$WORKSPACE_DIR/output/"*

# ─────────────────────────────────────────────────────────────
# 4. Final Environment Setup
# ─────────────────────────────────────────────────────────────

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Launch VSCode
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/run_pipeline.py &"
    sleep 5
fi

# Wait for VS Code window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

# Maximize and focus VS Code
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Open an integrated terminal and show the initial slow run times
su - ga -c "DISPLAY=:1 xdotool key ctrl+grave"
sleep 2
su - ga -c "DISPLAY=:1 xdotool type 'cat /tmp/initial_pipeline_run.log'"
su - ga -c "DISPLAY=:1 xdotool key Return"
sleep 1
su - ga -c "DISPLAY=:1 xdotool type 'clear'"
su - ga -c "DISPLAY=:1 xdotool key Return"

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="