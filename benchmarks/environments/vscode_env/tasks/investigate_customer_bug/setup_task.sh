#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Customer Bug Investigation Task ==="

WORKSPACE_DIR="/home/ga/workspace/analytics_app"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create support ticket file
cat > "$WORKSPACE_DIR/support_ticket_2847.txt" << 'EOF'
================================================================
SUPPORT TICKET #2847
================================================================
Priority: HIGH
Customer: TechCorp Inc (Account #4521)  
Reported: 2024-01-15 14:32 UTC
Assigned To: Engineering Team

ISSUE: Incorrect export totals when filtering by date range

CUSTOMER MESSAGE:
"When we export our sales data for Q1 2024 (specifically 
January 1 through March 31), the total revenue shown in 
the export is $45,230.

However, our internal accounting system shows the correct 
total should be $52,150 for that exact same period.

We've attached a CSV with sample transactions from our 
database. Please investigate urgently as this is affecting 
our quarterly financial reporting to stakeholders."

ATTACHMENT: customer_data_sample.csv

SUPPORT AGENT NOTES:
- Customer using "Export by Date Range" feature
- Date range specified: 2024-01-01 to 2024-03-31 (inclusive)
- No error messages displayed to user
- Issue reproduces consistently on their production data
- Customer is a premium account, high visibility

NEXT STEPS:
Engineering to investigate and provide root cause analysis.
================================================================
EOF

# Create customer sample data CSV
cat > "$WORKSPACE_DIR/customer_data_sample.csv" << 'EOF'
transaction_id,date,amount,customer_id,product
T1001,2024-01-15,1250.00,C401,Widget A
T1002,2024-01-20,890.50,C402,Widget B
T1003,2024-02-05,2100.00,C403,Widget C
T1004,2024-02-18,1575.25,C401,Widget A
T1005,2024-03-01,3200.00,C404,Widget D
T1006,2024-03-15,1890.00,C402,Widget B
T1007,2024-03-31,5500.00,C405,Widget E
T1008,2024-04-05,950.00,C401,Widget A
T1009,2024-04-12,1200.00,C403,Widget C
EOF

# Create main export handler
cat > "$WORKSPACE_DIR/src/export_handler.py" << 'EOF'
"""
Main export handler for analytics reports
"""
from datetime import datetime
from date_utils import filter_by_date_range
from calculations import calculate_total
from formatters import format_currency

def export_date_range(transactions, start_date, end_date):
    """
    Export transactions for a specific date range
    
    Args:
        transactions: List of transaction dicts
        start_date: Start date string (YYYY-MM-DD)
        end_date: End date string (YYYY-MM-DD)
    
    Returns:
        Dictionary with filtered transactions and total
    """
    filtered = filter_by_date_range(transactions, start_date, end_date)
    total = calculate_total(filtered)
    
    return {
        'transactions': filtered,
        'total': format_currency(total),
        'count': len(filtered),
        'date_range': f"{start_date} to {end_date}"
    }
EOF

# Create date utilities - THIS FILE CONTAINS THE BUG
cat > "$WORKSPACE_DIR/src/date_utils.py" << 'EOF'
"""
Date filtering utilities for transaction processing
"""
from datetime import datetime

def filter_by_date_range(transactions, start_date, end_date):
    """
    Filter transactions within a date range.
    
    Args:
        transactions: List of transaction dicts with 'date' field
        start_date: Start date string YYYY-MM-DD (inclusive)
        end_date: End date string YYYY-MM-DD (inclusive)
    
    Returns:
        List of transactions within the date range
    """
    filtered = []
    for txn in transactions:
        txn_date = datetime.strptime(txn['date'], '%Y-%m-%d')
        start = datetime.strptime(start_date, '%Y-%m-%d')
        end = datetime.strptime(end_date, '%Y-%m-%d')
        
        if start <= txn_date < end:
            filtered.append(txn)
    
    return filtered

def parse_date(date_string):
    """Parse date string to datetime object"""
    return datetime.strptime(date_string, '%Y-%m-%d')
EOF

# Create calculations module
cat > "$WORKSPACE_DIR/src/calculations.py" << 'EOF'
"""
Revenue calculation functions
"""

def calculate_total(transactions):
    """Calculate total amount from transactions"""
    return sum(float(txn['amount']) for txn in transactions)

def calculate_average(transactions):
    """Calculate average transaction amount"""
    if not transactions:
        return 0.0
    return calculate_total(transactions) / len(transactions)
EOF

# Create formatters module
cat > "$WORKSPACE_DIR/src/formatters.py" << 'EOF'
"""
Output formatting utilities
"""

def format_currency(amount):
    """Format number as currency"""
    return f"${amount:,.2f}"

def format_date(date_obj):
    """Format datetime as string"""
    return date_obj.strftime('%Y-%m-%d')
EOF

# Create test file
cat > "$WORKSPACE_DIR/tests/test_exports.py" << 'EOF'
"""
Tests for export functionality
"""
import sys
sys.path.insert(0, '../src')

from date_utils import filter_by_date_range

def test_basic_date_filter():
    """Test basic date filtering"""
    transactions = [
        {'date': '2024-01-15', 'amount': '100.00'},
        {'date': '2024-02-15', 'amount': '200.00'},
        {'date': '2024-03-15', 'amount': '300.00'},
    ]
    
    result = filter_by_date_range(transactions, '2024-02-01', '2024-03-01')
    assert len(result) == 1
    assert result[0]['date'] == '2024-02-15'

# Note: No test for end date inclusivity bug!
EOF

# Create project README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Analytics App

Internal analytics and reporting application.

## Structure
- `src/` - Source code
  - `export_handler.py` - Main export logic
  - `date_utils.py` - Date filtering utilities  
  - `calculations.py` - Revenue calculations
  - `formatters.py` - Output formatting
- `tests/` - Test suite
- `support_ticket_2847.txt` - Current bug investigation
- `customer_data_sample.csv` - Sample data from customer

## Common Issues
- Check date format is YYYY-MM-DD
- Ensure timezone handling is correct
- Verify currency calculations for rounding

## Investigation Notes
See support_ticket_2847.txt for details on current Q1 2024 export bug.
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode with analytics_app workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Customer Bug Investigation Task Setup Complete ==="
echo "📋 Workspace: $WORKSPACE_DIR"
echo "📝 Instructions:"
echo "  1. Read support_ticket_2847.txt to understand the bug report"
echo "  2. Examine customer_data_sample.csv to see transaction data"
echo "  3. Use Ctrl+Shift+F to search for 'filter' or 'date_range' in codebase"
echo "  4. Find the bug in src/date_utils.py (hint: date comparison logic)"
echo "  5. Add a TODO/FIXME comment documenting the off-by-one error"
echo "  6. Save the file (Ctrl+S)"