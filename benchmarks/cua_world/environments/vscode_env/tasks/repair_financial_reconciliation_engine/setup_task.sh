#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair Financial Reconciliation Engine Task ==="

WORKSPACE_DIR="/home/ga/workspace/reconciliation_engine"
sudo -u ga mkdir -p "$WORKSPACE_DIR/engine"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"

# ──────────────────────────────────────────────────────────
# 1. Generate realistic bank statement CSV (~50 entries)
# ──────────────────────────────────────────────────────────
echo "Generating bank statement data..."

python3 << 'PYDATA' > "$WORKSPACE_DIR/data/bank_statement.csv"
import csv, sys, random
from decimal import Decimal

random.seed(101)

writer = csv.writer(sys.stdout)
writer.writerow(["date", "amount", "currency", "reference", "description"])

# Fixed entries designed to trigger specific bugs
rows = [
    # Standard USD transactions (should match cleanly)
    ("2024-01-02", "1500.50", "USD", "REF001", "Wire transfer - Acme Corp"),
    ("2024-01-02", "-2300.00", "USD", "REF002", "Vendor payment - SupplierCo"),
    ("2024-01-03", "8750.25", "USD", "REF003", "Customer deposit - Baker Industries"),
    ("2024-01-04", "-1200.00", "USD", "REF004", "Payroll - January wk1"),
    ("2024-01-05", "3320.10", "USD", "REF005", "ACH receipt - GlobalTech"),
    # Float precision traps (amounts that cause float issues)
    ("2024-01-08", "100.10", "USD", "REF006", "Wire - Precision Parts Inc"),
    ("2024-01-08", "-299.70", "USD", "REF007", "Payment - TripleNine LLC"),
    ("2024-01-09", "1000.30", "USD", "REF008", "Deposit - FloatTest Corp"),
    ("2024-01-09", "-50.10", "USD", "REF009", "Fee - Bank service charge"),
    ("2024-01-10", "200.20", "USD", "REF010", "Transfer - RoundingCo"),
    # Foreign currency transactions (FX spread bug)
    ("2024-01-10", "4642.84", "EUR", "REF011", "International receipt - EuroTrader GmbH"),
    ("2024-01-11", "-3174.88", "GBP", "REF012", "Wire out - London Suppliers Ltd"),
    ("2024-01-12", "67100.00", "JPY", "REF013", "Receipt - Tokyo Electronics"),
    ("2024-01-15", "2223.60", "CAD", "REF014", "Transfer - MapleCorp"),
    ("2024-01-15", "-5649.00", "CHF", "REF015", "Payment - Swiss Precision AG"),
    ("2024-01-16", "10842.00", "EUR", "REF016", "Wire - Frankfurt Holdings"),
    ("2024-01-17", "-6347.50", "GBP", "REF017", "Payment - Birmingham Steel"),
    # Timezone edge cases (near midnight UTC)
    ("2024-01-18", "5500.00", "USD", "REF018", "Wire - MidnightTrade Inc"),
    ("2024-01-19", "-4200.00", "USD", "REF019", "Vendor - LateNight Services"),
    ("2024-01-20", "7800.00", "USD", "REF020", "Deposit - CrossDay Corp"),
    ("2024-01-21", "-3100.00", "USD", "REF021", "Payment - EveningPay LLC"),
    ("2024-01-22", "6250.00", "USD", "REF022", "Transfer - TimezoneTest"),
    # Tolerance edge cases (large ledger aggregations)
    ("2024-01-22", "950.00", "USD", "REF023", "Partial payment - BigProject"),
    ("2024-01-23", "-15000.00", "USD", "REF024", "Wire out - MegaVendor"),
    ("2024-01-24", "500.00", "USD", "REF025", "Deposit - SmallCo"),
    # Exception report bug triggers (equal abs amounts, opposite signs)
    ("2024-01-25", "2500.00", "USD", "REF026", "Wire in - DebitCredit Inc"),
    ("2024-01-25", "-2500.00", "USD", "REF027", "Wire out - DebitCredit Inc"),
    ("2024-01-26", "750.00", "USD", "REF028", "Transfer in - SignTest"),
    ("2024-01-26", "-750.00", "USD", "REF029", "Transfer out - SignTest"),
    ("2024-01-27", "1800.00", "USD", "REF030", "Deposit - ABS Group"),
    # Additional realistic transactions
    ("2024-01-28", "-420.50", "USD", "REF031", "Utility payment - PowerGrid"),
    ("2024-01-28", "12500.00", "USD", "REF032", "Customer wire - Stellar Systems"),
    ("2024-01-29", "-8900.00", "USD", "REF033", "Vendor payment - CloudHost Inc"),
    ("2024-01-29", "3475.25", "USD", "REF034", "ACH deposit - RetailChain"),
    ("2024-01-30", "-1650.00", "USD", "REF035", "Insurance premium - SafeGuard"),
    ("2024-01-30", "22000.00", "USD", "REF036", "Wire - Institutional Investor A"),
    ("2024-01-31", "-5500.00", "USD", "REF037", "Loan payment - CreditBank"),
    ("2024-01-31", "4100.00", "USD", "REF038", "Deposit - ManufactureCo"),
    ("2024-01-31", "-975.00", "USD", "REF039", "Office supplies - OfficeMart"),
    ("2024-01-31", "18250.00", "USD", "REF040", "Quarter settlement - ClearingHouse"),
    # More FX
    ("2024-01-31", "3500.00", "EUR", "REF041", "Wire - Amsterdam Trade BV"),
    ("2024-01-31", "-8500.00", "GBP", "REF042", "Payment - Edinburgh Financial"),
    # More float precision traps
    ("2024-01-15", "33.33", "USD", "REF043", "Micro-deposit test 1"),
    ("2024-01-15", "66.67", "USD", "REF044", "Micro-deposit test 2"),
    ("2024-01-16", "-99.99", "USD", "REF045", "Refund - PrecisionRefund Co"),
    ("2024-01-17", "1234.56", "USD", "REF046", "Wire - DigitPattern Inc"),
    ("2024-01-20", "-4567.89", "USD", "REF047", "Payment - LargeDecimal LLC"),
    ("2024-01-22", "7777.77", "USD", "REF048", "Lucky deposit - CasinoCorp"),
    ("2024-01-24", "-3210.05", "USD", "REF049", "Vendor - ReverseCo"),
    ("2024-01-28", "15050.50", "USD", "REF050", "Wire - HalfPenny Financial"),
]

for row in rows:
    writer.writerow(row)
PYDATA

echo "Bank statement generated (50 entries)."

# ──────────────────────────────────────────────────────────
# 2. Generate matching internal ledger CSV (~50 entries)
# ──────────────────────────────────────────────────────────
echo "Generating internal ledger data..."

python3 << 'PYDATA' > "$WORKSPACE_DIR/data/internal_ledger.csv"
import csv, sys

writer = csv.writer(sys.stdout)
writer.writerow(["date", "amount", "currency", "reference", "description", "account_code"])

# Ledger entries that correspond to bank statement entries
# Some with slight variations that trigger bugs
rows = [
    # Standard USD (should match)
    ("2024-01-02", "1500.50", "USD", "REF001", "Customer payment - Acme Corp", "1010"),
    ("2024-01-02", "-2300.00", "USD", "REF002", "AP - SupplierCo", "2010"),
    ("2024-01-03", "8750.25", "USD", "REF003", "AR - Baker Industries", "1010"),
    ("2024-01-04", "-1200.00", "USD", "REF004", "Payroll Jan wk1", "5010"),
    ("2024-01-05", "3320.10", "USD", "REF005", "ACH - GlobalTech", "1010"),
    # Float precision: these are the SAME logical amounts but may differ in float representation
    # 100.10 = 100 + 0.1 which is exact in float, but let's use amounts that aren't
    ("2024-01-08", "100.10", "USD", "REF006", "AR - Precision Parts", "1010"),
    ("2024-01-08", "-299.70", "USD", "REF007", "AP - TripleNine", "2010"),
    ("2024-01-09", "1000.30", "USD", "REF008", "AR - FloatTest", "1010"),
    ("2024-01-09", "-50.10", "USD", "REF009", "Bank fee", "6010"),
    ("2024-01-10", "200.20", "USD", "REF010", "AR - RoundingCo", "1010"),
    # FX transactions - ledger records at mid-rate, bank uses spread-adjusted rate
    ("2024-01-10", "4642.84", "EUR", "REF011", "AR - EuroTrader GmbH", "1020"),
    ("2024-01-11", "-3174.88", "GBP", "REF012", "AP - London Suppliers", "2020"),
    ("2024-01-12", "67100.00", "JPY", "REF013", "AR - Tokyo Electronics", "1020"),
    ("2024-01-15", "2223.60", "CAD", "REF014", "AR - MapleCorp", "1020"),
    ("2024-01-15", "-5649.00", "CHF", "REF015", "AP - Swiss Precision", "2020"),
    ("2024-01-16", "10842.00", "EUR", "REF016", "AR - Frankfurt Holdings", "1020"),
    ("2024-01-17", "-6347.50", "GBP", "REF017", "AP - Birmingham Steel", "2020"),
    # Timezone edge cases: ledger recorded in US/Eastern, bank in UTC
    # These dates differ by 1 day due to timezone (bank: 18th UTC = ledger: 17th ET near midnight)
    ("2024-01-17", "5500.00", "USD", "REF018", "AR - MidnightTrade", "1010"),
    ("2024-01-18", "-4200.00", "USD", "REF019", "AP - LateNight Services", "2010"),
    ("2024-01-19", "7800.00", "USD", "REF020", "AR - CrossDay Corp", "1010"),
    ("2024-01-20", "-3100.00", "USD", "REF021", "AP - EveningPay", "2010"),
    ("2024-01-21", "6250.00", "USD", "REF022", "AR - TimezoneTest", "1010"),
    # Tolerance edge: ledger has aggregated amount larger than bank's partial
    ("2024-01-22", "960.00", "USD", "REF023", "AR - BigProject (partial 1+2)", "1010"),
    ("2024-01-23", "-15000.00", "USD", "REF024", "AP - MegaVendor", "2010"),
    ("2024-01-24", "500.00", "USD", "REF025", "AR - SmallCo", "1010"),
    # Exception report triggers - these should NOT match and should stay as separate exceptions
    ("2024-01-25", "2500.00", "USD", "REF026", "AR - DebitCredit Inc", "1010"),
    ("2024-01-25", "-2500.00", "USD", "REF027", "AP - DebitCredit Inc", "2010"),
    ("2024-01-26", "750.00", "USD", "REF028", "AR - SignTest", "1010"),
    ("2024-01-26", "-750.00", "USD", "REF029", "AP - SignTest", "2010"),
    ("2024-01-27", "1800.00", "USD", "REF030", "AR - ABS Group", "1010"),
    # Additional realistic transactions
    ("2024-01-28", "-420.50", "USD", "REF031", "AP - PowerGrid utility", "6020"),
    ("2024-01-28", "12500.00", "USD", "REF032", "AR - Stellar Systems", "1010"),
    ("2024-01-29", "-8900.00", "USD", "REF033", "AP - CloudHost Inc", "2010"),
    ("2024-01-29", "3475.25", "USD", "REF034", "AR - RetailChain", "1010"),
    ("2024-01-30", "-1650.00", "USD", "REF035", "AP - SafeGuard Insurance", "6030"),
    ("2024-01-30", "22000.00", "USD", "REF036", "AR - Institutional Investor A", "1010"),
    ("2024-01-31", "-5500.00", "USD", "REF037", "AP - CreditBank loan", "2030"),
    ("2024-01-31", "4100.00", "USD", "REF038", "AR - ManufactureCo", "1010"),
    ("2024-01-31", "-975.00", "USD", "REF039", "AP - OfficeMart supplies", "6040"),
    ("2024-01-31", "18250.00", "USD", "REF040", "AR - ClearingHouse settlement", "1010"),
    # More FX
    ("2024-01-31", "3500.00", "EUR", "REF041", "AR - Amsterdam Trade BV", "1020"),
    ("2024-01-31", "-8500.00", "GBP", "REF042", "AP - Edinburgh Financial", "2020"),
    # More float precision
    ("2024-01-15", "33.33", "USD", "REF043", "AR - Micro deposit 1", "1010"),
    ("2024-01-15", "66.67", "USD", "REF044", "AR - Micro deposit 2", "1010"),
    ("2024-01-16", "-99.99", "USD", "REF045", "AP - PrecisionRefund", "2010"),
    ("2024-01-17", "1234.56", "USD", "REF046", "AR - DigitPattern", "1010"),
    ("2024-01-20", "-4567.89", "USD", "REF047", "AP - LargeDecimal", "2010"),
    ("2024-01-22", "7777.77", "USD", "REF048", "AR - CasinoCorp", "1010"),
    ("2024-01-24", "-3210.05", "USD", "REF049", "AP - ReverseCo", "2010"),
    ("2024-01-28", "15050.50", "USD", "REF050", "AR - HalfPenny Financial", "1010"),
]

for row in rows:
    writer.writerow(row)
PYDATA

echo "Internal ledger generated (50 entries)."

# ──────────────────────────────────────────────────────────
# 3. config.py (correct, no bugs)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
"""Reconciliation engine configuration."""
from decimal import Decimal

# Matching parameters
AMOUNT_TOLERANCE_PERCENT = Decimal('0.01')  # 1% tolerance
MAX_DATE_OFFSET_DAYS = 2  # Allow 2 business day offset
FX_SPREAD_PERCENT = Decimal('0.005')  # 0.5% bid/ask spread

# Currency settings
BASE_CURRENCY = 'USD'
FX_RATES = {
    'EUR_USD': Decimal('1.0842'),
    'GBP_USD': Decimal('1.2695'),
    'JPY_USD': Decimal('0.00671'),
    'CAD_USD': Decimal('0.7412'),
    'CHF_USD': Decimal('1.1298'),
}

# Timezone settings
BANK_TIMEZONE = 'UTC'
LEDGER_TIMEZONE = 'US/Eastern'

# Output
EXCEPTION_REPORT_PATH = 'output/exceptions.csv'
MATCH_REPORT_PATH = 'output/matches.csv'
EOF

# ──────────────────────────────────────────────────────────
# 4. engine/__init__.py
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/__init__.py" << 'EOF'
# Reconciliation engine package
EOF

# ──────────────────────────────────────────────────────────
# 5. engine/matcher.py (BUG: float equality for amount comparison)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/matcher.py" << 'PYEOF'
"""Transaction matching engine."""
from engine.date_handler import normalize_dates
from engine.fx_handler import convert_to_base
from engine.tolerance_checker import within_tolerance

class TransactionMatcher:
    def __init__(self, config):
        self.config = config
        self.matches = []
        self.bank_exceptions = []
        self.ledger_exceptions = []

    def match_transactions(self, bank_entries, ledger_entries):
        """Match bank statement entries against internal ledger."""
        used_ledger = set()

        for bank_entry in bank_entries:
            bank_amount = float(bank_entry['amount'])
            bank_date = bank_entry['date']
            bank_ref = bank_entry.get('reference', '')
            best_match = None
            best_score = 0

            for i, ledger_entry in enumerate(ledger_entries):
                if i in used_ledger:
                    continue

                ledger_amount = float(ledger_entry['amount'])

                # Compare bank and ledger amounts for exact match
                # Score 100 for matching amounts, 0 otherwise
                if bank_amount == ledger_amount:
                    amount_score = 100
                else:
                    amount_score = 0

                # Date proximity scoring
                date_score = self._date_proximity_score(bank_date, ledger_entry['date'])

                # Reference matching
                ref_score = self._reference_score(bank_ref, ledger_entry.get('reference', ''))

                total_score = amount_score * 0.5 + date_score * 0.3 + ref_score * 0.2

                if total_score > best_score and amount_score > 0:
                    best_score = total_score
                    best_match = i

            if best_match is not None:
                self.matches.append({
                    'bank': bank_entry,
                    'ledger': ledger_entries[best_match],
                    'score': best_score
                })
                used_ledger.add(best_match)
            else:
                self.bank_exceptions.append(bank_entry)

        # Remaining unmatched ledger entries
        for i, entry in enumerate(ledger_entries):
            if i not in used_ledger:
                self.ledger_exceptions.append(entry)

        return {
            'matches': self.matches,
            'bank_exceptions': self.bank_exceptions,
            'ledger_exceptions': self.ledger_exceptions
        }

    def _date_proximity_score(self, date1, date2):
        """Score based on date proximity."""
        from datetime import datetime
        try:
            d1 = datetime.strptime(str(date1)[:10], '%Y-%m-%d')
            d2 = datetime.strptime(str(date2)[:10], '%Y-%m-%d')
            diff = abs((d1 - d2).days)
            if diff == 0:
                return 100
            elif diff <= self.config.get('max_date_offset', 2):
                return 50
            return 0
        except (ValueError, TypeError):
            return 0

    def _reference_score(self, ref1, ref2):
        """Score based on reference number similarity."""
        if not ref1 or not ref2:
            return 0
        if ref1.strip().lower() == ref2.strip().lower():
            return 100
        if ref1.strip() in ref2.strip() or ref2.strip() in ref1.strip():
            return 50
        return 0
PYEOF

# ──────────────────────────────────────────────────────────
# 6. engine/fx_handler.py (BUG: no bid/ask spread applied)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/fx_handler.py" << 'PYEOF'
"""Foreign exchange handling for multi-currency reconciliation."""
from decimal import Decimal, ROUND_HALF_UP
from config import FX_RATES, BASE_CURRENCY, FX_SPREAD_PERCENT

class FXHandler:
    def __init__(self):
        self.rates = FX_RATES
        self.spread = FX_SPREAD_PERCENT

    def convert_to_base(self, amount, currency, direction='buy'):
        """Convert a foreign currency amount to base currency (USD).

        Args:
            amount: Amount in foreign currency
            currency: Source currency code
            direction: 'buy' or 'sell' for spread application

        Returns:
            Amount in base currency
        """
        if currency == BASE_CURRENCY:
            return Decimal(str(amount))

        rate_key = f"{currency}_{BASE_CURRENCY}"
        if rate_key not in self.rates:
            raise ValueError(f"No FX rate for {rate_key}")

        mid_rate = self.rates[rate_key]

        # Convert using the mid-market rate for this currency pair
        # The effective rate is used to translate amounts between currencies
        effective_rate = mid_rate  # Should apply spread based on direction

        converted = Decimal(str(amount)) * effective_rate
        return converted.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

    def get_rate(self, currency, direction='mid'):
        """Get exchange rate for a currency pair."""
        rate_key = f"{currency}_{BASE_CURRENCY}"
        if rate_key not in self.rates:
            return None

        mid = self.rates[rate_key]
        if direction == 'buy':
            return mid * (1 + self.spread)
        elif direction == 'sell':
            return mid * (1 - self.spread)
        return mid


def convert_to_base(amount, currency, direction='buy'):
    """Module-level convenience function."""
    handler = FXHandler()
    return handler.convert_to_base(amount, currency, direction)
PYEOF

# ──────────────────────────────────────────────────────────
# 7. engine/date_handler.py (BUG: timezone-naive comparison)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/date_handler.py" << 'PYEOF'
"""Date handling and business day calculations."""
from datetime import datetime, timedelta
from config import BANK_TIMEZONE, LEDGER_TIMEZONE, MAX_DATE_OFFSET_DAYS

def normalize_dates(bank_date_str, ledger_date_str):
    """Normalize dates from bank and ledger for comparison.

    Bank dates are in UTC, ledger dates are in US/Eastern.
    Both should be normalized to the same timezone for comparison.
    """
    # Parse the date strings into datetime objects for comparison
    # Extract just the date portion (first 10 characters) from each string
    bank_date = datetime.strptime(str(bank_date_str)[:10], '%Y-%m-%d')
    ledger_date = datetime.strptime(str(ledger_date_str)[:10], '%Y-%m-%d')

    return bank_date, ledger_date

def dates_within_range(date1, date2, max_days=MAX_DATE_OFFSET_DAYS):
    """Check if two dates are within the allowed range."""
    if isinstance(date1, str):
        date1 = datetime.strptime(date1[:10], '%Y-%m-%d')
    if isinstance(date2, str):
        date2 = datetime.strptime(date2[:10], '%Y-%m-%d')

    diff = abs((date1 - date2).days)
    return diff <= max_days

def get_business_date(date, timezone=None):
    """Get the business date, adjusting for weekends."""
    if isinstance(date, str):
        date = datetime.strptime(date[:10], '%Y-%m-%d')

    # Skip weekends
    while date.weekday() >= 5:  # Saturday=5, Sunday=6
        date += timedelta(days=1)

    return date

def is_business_day(date):
    """Check if a date is a business day."""
    if isinstance(date, str):
        date = datetime.strptime(date[:10], '%Y-%m-%d')
    return date.weekday() < 5
PYEOF

# ──────────────────────────────────────────────────────────
# 8. engine/tolerance_checker.py (BUG: wrong tolerance base)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/tolerance_checker.py" << 'PYEOF'
"""Amount tolerance checking for reconciliation matching."""
from decimal import Decimal
from config import AMOUNT_TOLERANCE_PERCENT

def within_tolerance(bank_amount, ledger_amount, tolerance_pct=AMOUNT_TOLERANCE_PERCENT):
    """Check if two amounts are within the configured tolerance.

    The tolerance should be calculated as a percentage of the
    larger of the two amounts being compared.
    """
    bank_dec = Decimal(str(bank_amount))
    ledger_dec = Decimal(str(ledger_amount))

    diff = abs(bank_dec - ledger_dec)

    # Calculate the tolerance threshold based on the bank amount
    # Amounts within this percentage are considered matching
    tolerance_amount = abs(bank_dec) * tolerance_pct

    return diff <= tolerance_amount
PYEOF

# ──────────────────────────────────────────────────────────
# 9. engine/exception_reporter.py (BUG: sign-blind grouping)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/exception_reporter.py" << 'PYEOF'
"""Exception reporting for unmatched transactions."""
import csv
import os
from collections import defaultdict
from config import EXCEPTION_REPORT_PATH

class ExceptionReporter:
    def __init__(self):
        self.exceptions = []

    def generate_report(self, bank_exceptions, ledger_exceptions, output_path=None):
        """Generate exception report for unmatched transactions."""
        if output_path is None:
            output_path = EXCEPTION_REPORT_PATH

        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        # Combine all exceptions
        all_exceptions = []
        for entry in bank_exceptions:
            all_exceptions.append({
                'source': 'bank',
                'date': entry.get('date', ''),
                'amount': float(entry.get('amount', 0)),
                'reference': entry.get('reference', ''),
                'description': entry.get('description', ''),
                'currency': entry.get('currency', 'USD')
            })
        for entry in ledger_exceptions:
            all_exceptions.append({
                'source': 'ledger',
                'date': entry.get('date', ''),
                'amount': float(entry.get('amount', 0)),
                'reference': entry.get('reference', ''),
                'description': entry.get('description', ''),
                'currency': entry.get('currency', 'USD')
            })

        # Group exceptions by amount for consolidated reporting
        grouped = defaultdict(list)
        for exc in all_exceptions:
            key = abs(exc['amount'])  # Use amount as the grouping key
            grouped[key].append(exc)

        # Write report
        with open(output_path, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['Group', 'Source', 'Date', 'Amount', 'Reference', 'Description', 'Currency'])

            for group_key, entries in sorted(grouped.items()):
                for entry in entries:
                    writer.writerow([
                        f"${group_key:.2f}",
                        entry['source'],
                        entry['date'],
                        entry['amount'],
                        entry['reference'],
                        entry['description'],
                        entry['currency']
                    ])

        return output_path, len(all_exceptions)
PYEOF

# ──────────────────────────────────────────────────────────
# 10. run_reconciliation.py (correct orchestrator, no bugs)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_reconciliation.py" << 'PYEOF'
"""Main reconciliation pipeline."""
import csv
import sys
import os
from engine.matcher import TransactionMatcher
from engine.exception_reporter import ExceptionReporter

def load_csv(filepath):
    """Load transactions from CSV."""
    entries = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            entries.append(row)
    return entries

def main():
    """Run reconciliation pipeline."""
    print("=== Bank Reconciliation Engine ===")

    # Load data
    bank_entries = load_csv('data/bank_statement.csv')
    ledger_entries = load_csv('data/internal_ledger.csv')

    print(f"Bank entries: {len(bank_entries)}")
    print(f"Ledger entries: {len(ledger_entries)}")

    # Match transactions
    config = {
        'max_date_offset': 2,
        'amount_tolerance': 0.01,
    }
    matcher = TransactionMatcher(config)
    results = matcher.match_transactions(bank_entries, ledger_entries)

    print(f"\nResults:")
    print(f"  Matched: {len(results['matches'])}")
    print(f"  Bank exceptions: {len(results['bank_exceptions'])}")
    print(f"  Ledger exceptions: {len(results['ledger_exceptions'])}")

    # Generate exception report
    reporter = ExceptionReporter()
    report_path, exc_count = reporter.generate_report(
        results['bank_exceptions'],
        results['ledger_exceptions']
    )
    print(f"  Exception report: {report_path} ({exc_count} entries)")

if __name__ == '__main__':
    main()
PYEOF

# ──────────────────────────────────────────────────────────
# 11. requirements.txt
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
# Reconciliation engine dependencies
EOF

# ──────────────────────────────────────────────────────────
# Ownership, baseline hashes, VSCode launch
# ──────────────────────────────────────────────────────────
chown -R ga:ga "$WORKSPACE_DIR"

# Record baseline hashes so the verifier can detect actual edits
md5sum \
    "$WORKSPACE_DIR/engine/matcher.py" \
    "$WORKSPACE_DIR/engine/fx_handler.py" \
    "$WORKSPACE_DIR/engine/date_handler.py" \
    "$WORKSPACE_DIR/engine/tolerance_checker.py" \
    "$WORKSPACE_DIR/engine/exception_reporter.py" \
    > /tmp/reconciliation_initial_hashes.txt

echo "Baseline hashes recorded."

# Open VSCode
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code --no-sandbox --disable-workspace-trust '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1
focus_vscode_window
sleep 3

echo "=== Repair Financial Reconciliation Engine Task Setup Complete ==="
echo "Workspace: $WORKSPACE_DIR"
echo "Pipeline entry point: run_reconciliation.py"
echo "The reconciliation engine has been producing incorrect results."
echo "Fix all issues before the month-end close deadline."
