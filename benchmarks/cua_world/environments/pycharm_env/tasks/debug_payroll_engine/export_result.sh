#!/bin/bash
echo "=== Exporting debug_payroll_engine results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/PycharmProjects/payroll_engine"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Pytest
echo "Running tests..."
cd "$PROJECT_DIR" || exit 1
# Install if needed (should be pre-installed in env, but ensuring)
# pip install pytest > /dev/null 2>&1

PYTEST_OUTPUT=$(python3 -m pytest tests/ -v 2>&1)
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED")
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED")

# 2. Static Analysis Check (Decimal usage)
# Check if currency.py imports Decimal and uses it
USES_DECIMAL="false"
if grep -q "from decimal import Decimal" "$PROJECT_DIR/payroll/currency.py" && \
   grep -q "Decimal(" "$PROJECT_DIR/payroll/currency.py"; then
    USES_DECIMAL="true"
fi

# 3. Ground Truth Verification (Hidden Test)
# Generate a hidden verification script that imports user code and tests edge cases
cat > /tmp/verify_payroll_hidden.py << 'PYEOF'
import sys
sys.path.insert(0, "/home/ga/PycharmProjects/payroll_engine")
import traceback
try:
    from payroll.calculator import calculate_income_tax, calculate_paycheck, calculate_overtime_pay
    from payroll.models import Employee, TimeEntry
    from payroll.currency import round_money
    
    score = 0
    details = []
    
    # Check 1: Progressive Tax Exact Value (Large Income)
    # Income 1,000,000 Single
    # Brackets 2024:
    # 10% on 11600 = 1160
    # 12% on (47150-11600) = 4266
    # 22% on (100525-47150) = 11742.5
    # 24% on (191950-100525) = 21942
    # 32% on (243725-191950) = 16568
    # 35% on (609350-243725) = 127968.75
    # 37% on (1000000-609350) = 144540.5
    # Total Tax = 328,187.75
    
    try:
        tax = calculate_income_tax(1000000, "single")
        # Allow small float error if they didn't use Decimal perfectly, but logic must be right
        # Buggy logic (flat 37%) would be 370,000.
        if abs(float(tax) - 328187.75) < 1.0:
            score += 1
        else:
            details.append(f"Hidden Tax Check: Expected ~328187.75, Got {tax}")
    except:
        details.append("Hidden Tax Check: Crash")

    # Check 2: SS Cap Exactness
    try:
        # YTD 168,500. Pay 200.
        # Taxable: 100. Tax: 6.20.
        emp = Employee(id="X", name="X", annual_salary=200000, ytd_earnings=168500)
        stub = calculate_paycheck(emp, 200)
        if abs(float(stub.social_security_tax) - 6.20) < 0.05:
            score += 1
        else:
            details.append(f"Hidden SS Check: Expected 6.20, Got {stub.social_security_tax}")
    except:
        details.append("Hidden SS Check: Crash")

    # Check 3: Overtime Weekly Split
    try:
        # W1: 45h. W2: 35h. Total 80h.
        # W1 OT: 5h. W2 OT: 0h. Total OT: 5h.
        # Pay: (75 * 10) + (5 * 10 * 1.5) = 750 + 75 = 825.
        # Buggy (80h total): 0 OT -> 800.
        entries = [TimeEntry("2024-01-01", 45), TimeEntry("2024-01-08", 35)]
        # Note: simplistic aggregation might fail if date parsing isn't implemented, 
        # but the task implies fixing the aggregation logic. 
        # Assuming user updated logic to handle dates or structure correctly.
        # If the user's function signature didn't change, they probably iterate entries.
        # To robustly test, we need to provide daily entries if their logic depends on days.
        entries_daily = []
        # 5 days of 9 hours = 45
        for i in range(1, 6): entries_daily.append(TimeEntry(f"2024-01-0{i}", 9))
        # 5 days of 7 hours = 35
        for i in range(8, 13): entries_daily.append(TimeEntry(f"2024-01-{i:02d}", 7))
        
        pay = calculate_overtime_pay(10, entries_daily)
        if abs(float(pay) - 825.00) < 0.1:
            score += 1
        else:
            details.append(f"Hidden OT Check: Expected 825.00, Got {pay}")
    except Exception as e:
        details.append(f"Hidden OT Check: Crash {e}")
        
    print(f"{score}|{';'.join(details)}")

except Exception as e:
    print(f"0|Import Error: {e}")
    traceback.print_exc()
PYEOF

HIDDEN_OUTPUT=$(python3 /tmp/verify_payroll_hidden.py)
HIDDEN_SCORE=$(echo "$HIDDEN_OUTPUT" | cut -d'|' -f1)
HIDDEN_DETAILS=$(echo "$HIDDEN_OUTPUT" | cut -d'|' -f2)

# Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "uses_decimal": $USES_DECIMAL,
    "hidden_score": $HIDDEN_SCORE,
    "hidden_details": "$HIDDEN_DETAILS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

mv "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="