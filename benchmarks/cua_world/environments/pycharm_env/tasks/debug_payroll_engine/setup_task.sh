#!/bin/bash
echo "=== Setting up debug_payroll_engine task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/payroll_engine"

# Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/debug_payroll_result.json 2>/dev/null || true

# Create Project Structure
su - ga -c "mkdir -p $PROJECT_DIR/payroll $PROJECT_DIR/tests $PROJECT_DIR/data"

# 1. Create Data (Tax Brackets)
cat > "$PROJECT_DIR/data/tax_brackets_2024.json" << 'JSON'
{
  "single": [
    {"limit": 11600, "rate": 0.10},
    {"limit": 47150, "rate": 0.12},
    {"limit": 100525, "rate": 0.22},
    {"limit": 191950, "rate": 0.24},
    {"limit": 243725, "rate": 0.32},
    {"limit": 609350, "rate": 0.35},
    {"limit": null, "rate": 0.37}
  ]
}
JSON

# 2. Create payroll/__init__.py
touch "$PROJECT_DIR/payroll/__init__.py"

# 3. Create payroll/models.py
cat > "$PROJECT_DIR/payroll/models.py" << 'PYEOF'
from dataclasses import dataclass
from typing import List

@dataclass
class TimeEntry:
    date: str  # YYYY-MM-DD
    hours: float

@dataclass
class Employee:
    id: str
    name: str
    annual_salary: float
    ytd_earnings: float = 0.0
    filing_status: str = "single"

@dataclass
class PayStub:
    gross_pay: float
    federal_tax: float
    social_security_tax: float
    medicare_tax: float
    net_pay: float
PYEOF

# 4. Create payroll/currency.py (BUG: Uses floats)
cat > "$PROJECT_DIR/payroll/currency.py" << 'PYEOF'
"""Currency utilities."""

# BUG: Auditors require Decimal, but this uses float
def round_money(amount: float) -> float:
    """Round to 2 decimal places."""
    return round(amount, 2)
PYEOF

# 5. Create payroll/calculator.py (Contains 3 Logic Bugs)
cat > "$PROJECT_DIR/payroll/calculator.py" << 'PYEOF'
import json
import os
from typing import List
from datetime import datetime
from payroll.models import Employee, TimeEntry, PayStub
from payroll.currency import round_money

# Constants
SS_RATE = 0.062
MEDICARE_RATE = 0.0145
# BUG: Missing SS_WAGE_BASE_LIMIT check in code, though constant might exist
SS_WAGE_BASE_LIMIT = 168600

def load_tax_brackets():
    path = os.path.join(os.path.dirname(__file__), '../data/tax_brackets_2024.json')
    with open(path) as f:
        return json.load(f)

def calculate_overtime_pay(hourly_rate: float, time_entries: List[TimeEntry]) -> float:
    """Calculate overtime pay for a 2-week pay period."""
    total_hours = sum(e.hours for e in time_entries)
    
    # BUG: Aggregates total hours for period (e.g. 80) instead of per-week (40)
    # If period is 2 weeks, overtime should be calculated per week.
    # Current logic: > 80 hours total = OT. 
    # Wrong for: Week 1 (60h), Week 2 (20h) -> Total 80h -> 0h OT (Should be 20h OT)
    
    regular_hours = min(total_hours, 80)
    overtime_hours = max(0, total_hours - 80)
    
    return round_money((regular_hours * hourly_rate) + (overtime_hours * hourly_rate * 1.5))

def calculate_income_tax(taxable_income: float, filing_status: str = "single") -> float:
    """Calculate Federal Income Tax."""
    brackets = load_tax_brackets()[filing_status]
    
    # BUG: Progressive Tax Logic Error
    # Finds the bracket the income falls into and applies that rate to the WHOLE income.
    # Should apply rates marginally to chunks of income.
    
    applicable_rate = 0.0
    for bracket in brackets:
        limit = bracket['limit']
        rate = bracket['rate']
        if limit is None or taxable_income <= limit:
            applicable_rate = rate
            break
            
    return round_money(taxable_income * applicable_rate)

def calculate_paycheck(employee: Employee, gross_pay: float) -> PayStub:
    """Calculate taxes and net pay."""
    
    # Federal Tax
    # Annualize to estimate tax bracket, then de-annualize (simplified for this task)
    annualized = gross_pay * 26
    annual_tax = calculate_income_tax(annualized, employee.filing_status)
    fed_tax = round_money(annual_tax / 26)
    
    # Social Security Tax
    # BUG: Does not check if ytd_earnings > SS_WAGE_BASE_LIMIT
    ss_tax = round_money(gross_pay * SS_RATE)
    
    # Medicare
    med_tax = round_money(gross_pay * MEDICARE_RATE)
    
    net_pay = gross_pay - fed_tax - ss_tax - med_tax
    
    return PayStub(
        gross_pay=round_money(gross_pay),
        federal_tax=fed_tax,
        social_security_tax=ss_tax,
        medicare_tax=med_tax,
        net_pay=round_money(net_pay)
    )
PYEOF

# 6. Create requirements.txt
echo "pytest>=7.0" > "$PROJECT_DIR/requirements.txt"

# 7. Create Tests
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
PYEOF

cat > "$PROJECT_DIR/tests/test_currency.py" << 'PYEOF'
from payroll.currency import round_money
from decimal import Decimal

def test_currency_precision():
    # Float math: 1.1 + 2.2 = 3.3000000000000003
    # This test asserts that the underlying type handles precision correctly
    # or that the rounding is stable.
    
    # A specific case where float rounding often fails pennies
    # 2.675 round(2) -> 2.67 in python float (rounds to nearest even sometimes or down)
    # Decimal(2.675) round(2, ROUND_HALF_UP) -> 2.68
    
    # We enforce that the return type should ideally not be float, 
    # OR that specific precision edge cases pass.
    
    # For this task, we check if the system can handle large numbers without losing penny precision
    # or simple addition
    
    val1 = 100.01
    val2 = 200.02
    # If refactored to Decimal, these strings would be used
    
    # Verify behavior on the classic float issue
    # If user switches to Decimal, this behavior changes
    pass
    
def test_decimal_usage():
    # The auditor specifically requested Decimal objects be used for intermediate calcs
    # We check if passing a string preserves precision
    result = round_money(2.675)
    # In standard python float round(2.675, 2) is 2.67 due to representation error
    # Financial standard usually requires 2.68 (Round Half Up)
    # The user must implement Decimal quantization to pass this if we enforce 2.68
    assert result == 2.68 or str(result) == '2.68', f"Expected 2.68 (financial rounding), got {result}"
PYEOF

cat > "$PROJECT_DIR/tests/test_tax.py" << 'PYEOF'
from payroll.calculator import calculate_income_tax, calculate_paycheck
from payroll.models import Employee

def test_tax_progressive_brackets():
    # Tax brackets 2024 Single:
    # 0 - 11,600: 10%
    # 11,601 - 47,150: 12%
    
    # Income: $20,000
    # First 11,600 @ 10% = 1,160
    # Remaining 8,400 @ 12% = 1,008
    # Total = 2,168
    
    # Buggy implementation does: 20,000 * 0.12 = 2,400 (Overcharge)
    
    tax = calculate_income_tax(20000, "single")
    assert abs(tax - 2168.00) < 0.01, f"Progressive tax failed. Expected 2168.00, got {tax}"

def test_ss_wage_base_limit():
    # Cap is 168,600
    # Emp has 168,000 YTD.
    # Current pay: 1,000.
    # Taxable for SS: 600 (to reach 168,600). Exempt: 400.
    # SS Tax = 600 * 0.062 = 37.20
    
    # Buggy implementation: 1000 * 0.062 = 62.00
    
    emp = Employee(id="E1", name="Richie", annual_salary=200000, ytd_earnings=168000)
    stub = calculate_paycheck(emp, 1000)
    
    assert abs(stub.social_security_tax - 37.20) < 0.01, \
        f"SS Tax cap failed. Expected 37.20, got {stub.social_security_tax}"

def test_ss_wage_base_already_met():
    # YTD 170,000. Current pay 1,000.
    # Taxable SS: 0.
    # SS Tax = 0.
    emp = Employee(id="E1", name="Richie", annual_salary=200000, ytd_earnings=170000)
    stub = calculate_paycheck(emp, 1000)
    
    assert stub.social_security_tax == 0.00, \
        f"SS Tax should be 0 above cap, got {stub.social_security_tax}"
PYEOF

cat > "$PROJECT_DIR/tests/test_overtime.py" << 'PYEOF'
from payroll.calculator import calculate_overtime_pay
from payroll.models import TimeEntry

def test_overtime_weekly_aggregation():
    # Week 1: 60 hours (should be 40 Reg + 20 OT)
    # Week 2: 20 hours (should be 20 Reg + 0 OT)
    # Total: 60 Reg + 20 OT.
    # Rate: $10/hr.
    # Pay: (60 * 10) + (20 * 10 * 1.5) = 600 + 300 = 900.
    
    # Buggy implementation (sums to 80 total, < 80 threshold? or just 80 limit):
    # Buggy logic: regular = min(80, 80) = 80. OT = 0.
    # Pay: 80 * 10 = 800.
    
    # Note: The provided calculator bug checks sum > 80.
    
    entries = [
        TimeEntry(date="2024-01-01", hours=12), # Mon W1
        TimeEntry(date="2024-01-02", hours=12), # Tue W1
        TimeEntry(date="2024-01-03", hours=12), # Wed W1
        TimeEntry(date="2024-01-04", hours=12), # Thu W1
        TimeEntry(date="2024-01-05", hours=12), # Fri W1 (Total W1: 60)
        
        TimeEntry(date="2024-01-08", hours=4),  # Mon W2
        TimeEntry(date="2024-01-09", hours=4),  # Tue W2
        TimeEntry(date="2024-01-10", hours=4),  # Wed W2
        TimeEntry(date="2024-01-11", hours=4),  # Thu W2
        TimeEntry(date="2024-01-12", hours=4),  # Fri W2 (Total W2: 20)
    ]
    # Total hours: 80.
    
    pay = calculate_overtime_pay(10.0, entries)
    assert abs(pay - 900.00) < 0.01, f"Overtime failed. Expected $900.00, got ${pay}"
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Open PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_startup.log 2>&1 &"

# Wait for PyCharm
source /workspace/scripts/task_utils.sh
wait_for_project_loaded "payroll_engine" 120
dismiss_dialogs
focus_pycharm_window

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="