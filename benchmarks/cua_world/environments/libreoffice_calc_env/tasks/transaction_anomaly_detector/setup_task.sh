#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Transaction Anomaly Detector Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Generate realistic transaction data with planted anomalies
python3 << 'PYEOF'
import csv
import random
from datetime import datetime, timedelta

# Set seed for reproducibility
random.seed(42)

# Transaction categories and typical ranges
categories = {
    'Groceries': (20, 150),
    'Restaurant': (15, 80),
    'Gas': (30, 90),
    'Coffee': (3, 15),
    'Utilities': (50, 200),
    'Shopping': (25, 300),
    'Entertainment': (20, 100),
    'Healthcare': (30, 250),
    'Transportation': (10, 50)
}

merchants = {
    'Groceries': ['Whole Foods', 'Safeway', 'Trader Joes', 'Local Market'],
    'Restaurant': ['Olive Garden', 'Chipotle', 'Local Bistro', 'Thai Palace'],
    'Gas': ['Shell', 'Chevron', 'BP', '76 Station'],
    'Coffee': ['Starbucks', 'Peets Coffee', 'Local Cafe', 'Dunkin'],
    'Utilities': ['PG&E', 'Water District', 'Internet Provider', 'Phone Company'],
    'Shopping': ['Target', 'Amazon', 'Best Buy', 'Mall Store'],
    'Entertainment': ['Movie Theater', 'Concert Hall', 'Streaming Service', 'Game Store'],
    'Healthcare': ['Pharmacy', 'Doctor Office', 'Dentist', 'Lab Corp'],
    'Transportation': ['Uber', 'Lyft', 'Metro Card', 'Parking']
}

# Generate base date (Q1 2024: Jan 1 - Mar 31)
start_date = datetime(2024, 1, 1)
end_date = datetime(2024, 3, 31)
date_range = (end_date - start_date).days

transactions = []
transaction_id = 1
running_balance = 5000.00  # Starting balance

# Generate 287 normal transactions
for _ in range(287):
    # Random date in Q1 2024
    random_days = random.randint(0, date_range)
    trans_date = start_date + timedelta(days=random_days)
    
    # Random category and merchant
    category = random.choice(list(categories.keys()))
    merchant = random.choice(merchants[category])
    
    # Amount within normal range for category
    min_amt, max_amt = categories[category]
    amount = round(random.uniform(min_amt, max_amt), 2)
    
    # All transactions are debits for simplicity
    trans_type = 'Debit'
    running_balance -= amount
    
    transactions.append({
        'id': transaction_id,
        'date': trans_date,
        'merchant': merchant,
        'category': category,
        'amount': amount,
        'type': trans_type,
        'balance': round(running_balance, 2)
    })
    transaction_id += 1

# Sort by date
transactions.sort(key=lambda x: x['date'])

# Recalculate running balance after sorting
running_balance = 5000.00
for trans in transactions:
    running_balance -= trans['amount']
    trans['balance'] = round(running_balance, 2)

# Now plant specific anomalies at known positions
anomaly_positions = {
    'duplicates': [(44, 45), (101, 102), (200, 201)],  # 0-indexed after header
    'future_dates': [77, 133],
    'ancient_dates': [55],
    'outliers': [22, 88, 155, 233],
    'impossible_amounts': [66, 177],
    'balance_errors': [98, 149, 219]
}

# Plant duplicates (copy transaction from previous row)
for idx1, idx2 in anomaly_positions['duplicates']:
    if idx1 < len(transactions) and idx2 < len(transactions):
        transactions[idx2] = transactions[idx1].copy()

# Plant future dates
for idx in anomaly_positions['future_dates']:
    if idx < len(transactions):
        future_date = datetime(2025, 6, 15) if idx == 77 else datetime(2026, 3, 20)
        transactions[idx]['date'] = future_date

# Plant ancient date
for idx in anomaly_positions['ancient_dates']:
    if idx < len(transactions):
        transactions[idx]['date'] = datetime(2015, 8, 10)

# Plant statistical outliers (amounts way above normal for category)
for idx in anomaly_positions['outliers']:
    if idx < len(transactions):
        category = transactions[idx]['category']
        # Make amount 5x the max normal range
        _, max_amt = categories[category]
        transactions[idx]['amount'] = round(max_amt * 5.0, 2)

# Plant impossible amounts
if 66 < len(transactions):
    transactions[66]['amount'] = 45000.00  # $45k coffee
    transactions[66]['category'] = 'Coffee'
    transactions[66]['merchant'] = 'Starbucks'

if 177 < len(transactions):
    transactions[177]['amount'] = -50.00  # Negative amount

# Plant balance calculation errors
for idx in anomaly_positions['balance_errors']:
    if idx < len(transactions):
        # Introduce error in balance calculation
        transactions[idx]['balance'] += 500.00

# Write to CSV
with open('/home/ga/Documents/transactions_corrupted.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['Date', 'Merchant', 'Category', 'Amount', 'Type', 'Balance'])
    
    for trans in transactions:
        writer.writerow([
            trans['date'].strftime('%Y-%m-%d'),
            trans['merchant'],
            trans['category'],
            trans['amount'],
            trans['type'],
            trans['balance']
        ])

print(f"✅ Generated {len(transactions)} transactions with planted anomalies")
print(f"   - {len(anomaly_positions['duplicates']) * 2} duplicate transactions")
print(f"   - {len(anomaly_positions['future_dates'])} future dates")
print(f"   - {len(anomaly_positions['ancient_dates'])} ancient dates")
print(f"   - {len(anomaly_positions['outliers'])} statistical outliers")
print(f"   - {len(anomaly_positions['impossible_amounts'])} impossible amounts")
print(f"   - {len(anomaly_positions['balance_errors'])} balance errors")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/transactions_corrupted.csv
sudo chmod 666 /home/ga/Documents/transactions_corrupted.csv

echo "✅ Transaction data created"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/transactions_corrupted.csv > /tmp/calc_anomaly_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_anomaly_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Position cursor at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Transaction Anomaly Detector Task Setup Complete ==="
echo "📋 Task: Identify and flag suspicious transactions"
echo "📊 Data: 287 transactions with 15 planted anomalies"
echo ""
echo "💡 Hints:"
echo "  • Add validation columns (e.g., 'Anomaly_Flags', 'Severity')"
echo "  • Use COUNTIFS for duplicate detection"
echo "  • Use AVERAGE and STDEV for outlier detection"
echo "  • Check dates with DATE functions and TODAY()"
echo "  • Apply conditional formatting for visual highlighting"
echo "  • Create summary showing count by anomaly type"