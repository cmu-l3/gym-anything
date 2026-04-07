#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug Distributed Payment System Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create directory structure
sudo -u ga mkdir -p services models tests

# ──────────────────────────────────────────────
# services/payment_processor.py  (BUG: float arithmetic for money)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/services/payment_processor.py" << 'PYEOF'
"""Core payment processing service."""
import json
import datetime
from services.currency_converter import CurrencyConverter
from services.transaction_validator import TransactionValidator
from services.ledger import Ledger
from services.idempotency import IdempotencyStore

class PaymentProcessor:
    def __init__(self):
        self.converter = CurrencyConverter()
        self.validator = TransactionValidator()
        self.ledger = Ledger()
        self.idempotency = IdempotencyStore()

    def process_payment(self, transaction):
        """Process a payment transaction."""
        # Check idempotency
        idempotency_key = transaction.get('idempotency_key', '')
        if self.idempotency.is_duplicate(idempotency_key):
            return {'status': 'duplicate', 'message': 'Transaction already processed'}

        # Validate
        validation = self.validator.validate(transaction)
        if not validation['valid']:
            return {'status': 'rejected', 'message': validation['reason']}

        # Convert amount to numeric type
        amount = float(transaction['amount'])
        source_currency = transaction.get('source_currency', 'USD')
        target_currency = transaction.get('target_currency', 'USD')

        # Convert if needed
        if source_currency != target_currency:
            amount = self.converter.convert(amount, source_currency, target_currency)

        # Calculate fees (2.5% processing fee)
        fee = amount * 0.025
        total = amount + fee

        # Record in ledger
        self.ledger.record_entry(
            transaction_id=transaction['id'],
            amount=total,
            entry_type='debit',
            account_type='liability',
            description=f"Payment {transaction['id']}"
        )

        # Store idempotency key
        self.idempotency.store(idempotency_key, transaction['id'])

        return {
            'status': 'success',
            'amount': amount,
            'fee': fee,
            'total': total,
            'currency': target_currency,
            'timestamp': datetime.datetime.utcnow().isoformat()
        }
PYEOF

# ──────────────────────────────────────────────
# services/currency_converter.py  (BUG: inverted FX rate)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/services/currency_converter.py" << 'PYEOF'
"""Currency conversion service using live exchange rates."""

class CurrencyConverter:
    # Exchange rates (base: USD)
    RATES = {
        'USD_EUR': 0.8547,
        'USD_GBP': 0.7312,
        'USD_JPY': 149.50,
        'USD_CAD': 1.3621,
        'USD_AUD': 1.5280,
        'USD_CHF': 0.8891,
        'EUR_GBP': 0.8554,
        'GBP_JPY': 204.46,
    }

    def convert(self, amount, source_currency, target_currency):
        """Convert amount from source to target currency."""
        if source_currency == target_currency:
            return amount

        direct_key = f"{source_currency}_{target_currency}"
        inverse_key = f"{target_currency}_{source_currency}"

        if direct_key in self.RATES:
            rate = self.RATES[direct_key]
            return amount * rate
        elif inverse_key in self.RATES:
            rate = self.RATES[inverse_key]
            # Apply the inverse conversion rate
            return amount * rate
        else:
            # Try two-step conversion through USD
            if source_currency != 'USD':
                to_usd = self.convert(amount, source_currency, 'USD')
                return self.convert(to_usd, 'USD', target_currency)
            raise ValueError(f"No rate found for {source_currency} to {target_currency}")
PYEOF

# ──────────────────────────────────────────────
# services/transaction_validator.py  (BUG: insufficient amount validation)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/services/transaction_validator.py" << 'PYEOF'
"""Transaction validation service."""

MAX_TRANSACTION_LIMIT = 1000000  # $1M limit

class TransactionValidator:
    REQUIRED_FIELDS = ['id', 'amount', 'source_currency']
    SUPPORTED_CURRENCIES = ['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD', 'CHF']

    def validate(self, transaction):
        """Validate a transaction before processing."""
        # Check required fields
        for field in self.REQUIRED_FIELDS:
            if field not in transaction:
                return {'valid': False, 'reason': f'Missing required field: {field}'}

        # Check currency support
        source = transaction.get('source_currency', 'USD')
        target = transaction.get('target_currency', 'USD')
        if source not in self.SUPPORTED_CURRENCIES:
            return {'valid': False, 'reason': f'Unsupported source currency: {source}'}
        if target not in self.SUPPORTED_CURRENCIES:
            return {'valid': False, 'reason': f'Unsupported target currency: {target}'}

        # Basic amount validation
        amount = transaction['amount']
        if amount > 0:
            return {'valid': True, 'reason': None}

        return {'valid': False, 'reason': 'Amount must be positive'}
PYEOF

# ──────────────────────────────────────────────
# services/ledger.py  (BUG: reversed debit/credit for liability accounts)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/services/ledger.py" << 'PYEOF'
"""Double-entry bookkeeping ledger."""
import datetime

class LedgerEntry:
    def __init__(self, transaction_id, amount, entry_type, account_type, description):
        self.transaction_id = transaction_id
        self.amount = amount
        self.entry_type = entry_type
        self.account_type = account_type
        self.description = description
        self.timestamp = datetime.datetime.utcnow()

class Ledger:
    def __init__(self):
        self.entries = []
        self.balances = {'asset': 0.0, 'liability': 0.0, 'revenue': 0.0}

    def record_entry(self, transaction_id, amount, entry_type, account_type, description=""):
        """Record a ledger entry and update balances."""
        entry = LedgerEntry(transaction_id, amount, entry_type, account_type, description)
        self.entries.append(entry)

        # Update balance based on entry type
        if entry_type == 'debit':
            self.balances[account_type] += amount
        elif entry_type == 'credit':
            self.balances[account_type] -= amount

        return entry

    def get_balance(self, account_type):
        """Get current balance for an account type."""
        return self.balances.get(account_type, 0.0)

    def get_entries(self, transaction_id=None):
        """Get ledger entries, optionally filtered by transaction ID."""
        if transaction_id:
            return [e for e in self.entries if e.transaction_id == transaction_id]
        return self.entries
PYEOF

# ──────────────────────────────────────────────
# services/idempotency.py  (BUG: case-sensitive key comparison)
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/services/idempotency.py" << 'PYEOF'
"""Idempotency key management for preventing duplicate transactions."""
import datetime

class IdempotencyStore:
    def __init__(self):
        self.keys = {}  # key -> {transaction_id, timestamp}
        self.ttl_seconds = 86400  # 24-hour TTL

    def is_duplicate(self, key):
        """Check if an idempotency key has been used."""
        if not key:
            return False

        self._cleanup_expired()

        # Check if key has been used before
        return key in self.keys

    def store(self, key, transaction_id):
        """Store an idempotency key."""
        if not key:
            return
        # Store the idempotency key
        self.keys[key] = {
            'transaction_id': transaction_id,
            'timestamp': datetime.datetime.utcnow()
        }

    def _cleanup_expired(self):
        """Remove expired idempotency keys."""
        now = datetime.datetime.utcnow()
        expired = [
            k for k, v in self.keys.items()
            if (now - v['timestamp']).total_seconds() > self.ttl_seconds
        ]
        for k in expired:
            del self.keys[k]
PYEOF

# ──────────────────────────────────────────────
# services/__init__.py
# ──────────────────────────────────────────────
touch "$WORKSPACE_DIR/services/__init__.py"

# ──────────────────────────────────────────────
# models/transaction.py
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/models/transaction.py" << 'PYEOF'
"""Transaction data model."""
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional
import uuid

@dataclass
class Transaction:
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
    amount: float = 0.0
    source_currency: str = 'USD'
    target_currency: str = 'USD'
    idempotency_key: str = ''
    status: str = 'pending'
    created_at: datetime = field(default_factory=datetime.utcnow)
    description: Optional[str] = None
PYEOF

# ──────────────────────────────────────────────
# models/account.py
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/models/account.py" << 'PYEOF'
"""Account data model."""
from dataclasses import dataclass, field
from datetime import datetime

@dataclass
class Account:
    id: str = ''
    name: str = ''
    account_type: str = 'asset'  # asset, liability, revenue
    balance: float = 0.0
    currency: str = 'USD'
    created_at: datetime = field(default_factory=datetime.utcnow)
PYEOF

# ──────────────────────────────────────────────
# models/__init__.py
# ──────────────────────────────────────────────
touch "$WORKSPACE_DIR/models/__init__.py"

# ──────────────────────────────────────────────
# tests/test_payments.py
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_payments.py" << 'PYEOF'
"""Payment system test suite. Some tests currently failing."""
import unittest
import sys
sys.path.insert(0, '/home/ga/workspace/payment_service')

from services.payment_processor import PaymentProcessor
from services.currency_converter import CurrencyConverter
from services.transaction_validator import TransactionValidator
from services.ledger import Ledger
from services.idempotency import IdempotencyStore


class TestCurrencyConverter(unittest.TestCase):
    def setUp(self):
        self.converter = CurrencyConverter()

    def test_direct_conversion(self):
        """USD to EUR direct conversion."""
        result = self.converter.convert(100, 'USD', 'EUR')
        self.assertAlmostEqual(result, 85.47, places=2)

    def test_inverse_conversion(self):
        """EUR to USD should use inverse rate."""
        # 100 EUR should be ~117 USD (100 / 0.8547)
        result = self.converter.convert(100, 'EUR', 'USD')
        self.assertAlmostEqual(result, 117.00, delta=1.0)

    def test_same_currency(self):
        result = self.converter.convert(100, 'USD', 'USD')
        self.assertEqual(result, 100)


class TestTransactionValidator(unittest.TestCase):
    def setUp(self):
        self.validator = TransactionValidator()

    def test_valid_transaction(self):
        txn = {'id': 'tx1', 'amount': 100.50, 'source_currency': 'USD'}
        result = self.validator.validate(txn)
        self.assertTrue(result['valid'])

    def test_exceeds_limit(self):
        """Should reject transactions over $1M."""
        txn = {'id': 'tx2', 'amount': 2000000, 'source_currency': 'USD'}
        result = self.validator.validate(txn)
        self.assertFalse(result['valid'])

    def test_negative_amount(self):
        txn = {'id': 'tx3', 'amount': -50, 'source_currency': 'USD'}
        result = self.validator.validate(txn)
        self.assertFalse(result['valid'])


class TestLedger(unittest.TestCase):
    def setUp(self):
        self.ledger = Ledger()

    def test_liability_debit_decreases(self):
        """Debit to liability account should decrease balance."""
        self.ledger.record_entry('tx1', 100, 'debit', 'liability')
        # For liability accounts, debits should DECREASE the balance
        self.assertEqual(self.ledger.get_balance('liability'), -100)

    def test_asset_debit_increases(self):
        """Debit to asset account should increase balance."""
        self.ledger.record_entry('tx1', 100, 'debit', 'asset')
        self.assertEqual(self.ledger.get_balance('asset'), 100)


class TestIdempotency(unittest.TestCase):
    def setUp(self):
        self.store = IdempotencyStore()

    def test_duplicate_detection(self):
        self.store.store('key-123', 'tx1')
        self.assertTrue(self.store.is_duplicate('key-123'))

    def test_case_insensitive(self):
        """Same key with different case should be detected as duplicate."""
        self.store.store('Payment-Key-ABC', 'tx1')
        self.assertTrue(self.store.is_duplicate('payment-key-abc'))


class TestPaymentProcessor(unittest.TestCase):
    def setUp(self):
        self.processor = PaymentProcessor()

    def test_decimal_precision(self):
        """Currency amounts must not have floating point errors."""
        txn = {
            'id': 'tx-precision',
            'amount': 0.1,
            'source_currency': 'USD',
            'target_currency': 'USD',
            'idempotency_key': 'prec-001'
        }
        result = self.processor.process_payment(txn)
        # 0.1 + 2.5% fee = 0.1025, should be exact
        self.assertEqual(str(result['total']), '0.1025')


if __name__ == '__main__':
    unittest.main()
PYEOF

# ──────────────────────────────────────────────
# main.py
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/main.py" << 'PYEOF'
"""Payment Service - Main Entry Point"""
from services.payment_processor import PaymentProcessor

def main():
    processor = PaymentProcessor()

    # Example transaction
    transaction = {
        'id': 'txn-001',
        'amount': 250.99,
        'source_currency': 'USD',
        'target_currency': 'EUR',
        'idempotency_key': 'idem-key-001'
    }

    result = processor.process_payment(transaction)
    print(f"Transaction result: {result}")

if __name__ == '__main__':
    main()
PYEOF

# ──────────────────────────────────────────────
# requirements.txt
# ──────────────────────────────────────────────
cat > "$WORKSPACE_DIR/requirements.txt" << 'PYEOF'
# Payment service dependencies
PYEOF

# ──────────────────────────────────────────────
# Record baseline hashes for verification
# ──────────────────────────────────────────────
md5sum "$WORKSPACE_DIR/services/"*.py > /tmp/payment_system_initial_hashes.txt

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code --no-sandbox --disable-workspace-trust '$WORKSPACE_DIR' &"
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Debug Distributed Payment System Task Setup Complete ==="
echo "Instructions:"
echo "  1. Review the payment service code in /home/ga/workspace/payment_service/"
echo "  2. Run tests: cd /home/ga/workspace/payment_service && python3 -m pytest tests/"
echo "  3. Identify and fix all bugs causing test failures"
echo "  4. Save all modified files (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"
