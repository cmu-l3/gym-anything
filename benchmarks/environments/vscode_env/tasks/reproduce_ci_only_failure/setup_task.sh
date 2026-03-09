#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Reproduce CI-Only Failure Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/payment_service"

# Install pytest if not already installed
if ! su - ga -c "python3 -c 'import pytest' 2>/dev/null"; then
    echo "Installing pytest..."
    su - ga -c "pip3 install --user pytest pytest-timeout" || true
fi

# Create __init__.py files
sudo -u ga touch "$WORKSPACE_DIR/payment_service/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/tests/__init__.py"

# Create models.py
cat > "$WORKSPACE_DIR/payment_service/models.py" << 'EOF'
class Payment:
    def __init__(self, amount, currency):
        self.amount = amount
        self.currency = currency
        self.status = "pending"
        self.confirmation_code = None
EOF

# Create processor.py (the buggy async implementation)
cat > "$WORKSPACE_DIR/payment_service/processor.py" << 'EOF'
import time
import threading
import random
import uuid

class PaymentProcessor:
    def __init__(self, mock_mode=False):
        self.mock_mode = mock_mode
        self.processing_delay = 0.1 if mock_mode else 2.0
    
    def submit(self, payment):
        """Submit payment for processing (async via thread)."""
        payment.status = "pending"
        
        # Simulate async processing
        def process():
            # Simulate variable processing time
            delay = self.processing_delay + random.uniform(0, 1.5)
            time.sleep(delay)
            payment.status = "completed"
            payment.confirmation_code = str(uuid.uuid4())[:12]
        
        thread = threading.Thread(target=process)
        thread.start()
        # NOTE: Not joining the thread - this causes the race condition!
EOF

# Create the FLAKY test (this is what needs to be fixed)
cat > "$WORKSPACE_DIR/tests/test_payment.py" << 'EOF'
import pytest
import time
from payment_service.processor import PaymentProcessor
from payment_service.models import Payment

@pytest.fixture
def processor():
    return PaymentProcessor(mock_mode=True)

def test_payment_processing(processor):
    """Test that payment processing completes successfully."""
    # Create a payment
    payment = Payment(amount=100.00, currency="USD")
    
    # Submit for processing
    processor.submit(payment)
    
    # Wait for processing to complete
    time.sleep(2)
    
    # Check status
    assert payment.status == "completed", f"Payment status still '{payment.status}' after 5 seconds"
    assert payment.confirmation_code is not None
    assert len(payment.confirmation_code) == 12
EOF

# Create CI failure log
cat > "$WORKSPACE_DIR/ci_failure_log.txt" << 'EOF'
====== CI Pipeline Failure Log ======
Test: test_payment_processing
Run: 2024-01-15 14:23:45 UTC
Environment: ubuntu-latest, Python 3.10, 2 CPU cores

FAILED tests/test_payment.py::test_payment_processing - AssertionError: Payment status still 'pending' after 5 seconds
Expected: 'completed'
Actual: 'pending'

Test duration: 5.03 seconds

Previous runs:
- Run #247: PASSED (1.89s)
- Run #246: FAILED (5.02s) <- Same error
- Run #245: PASSED (1.95s)
- Run #244: PASSED (2.01s)
- Run #243: FAILED (5.03s) <- Same error
- Run #242: PASSED (1.87s)

Pattern: Fails ~40% of the time in CI, never fails locally

Root cause: The PaymentProcessor.submit() runs in a background thread with variable
processing time (0.1 + random 0-1.5 seconds). Fixed time.sleep(2) doesn't guarantee
completion under CI load/timing variations.
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Payment Service

## The Problem

The `test_payment_processing` test is flaky in CI but passes locally.

**Symptom**: Test times out waiting for payment status to change from "pending" to "completed"

**Why**: The test uses `time.sleep(2)` to wait for async processing, but the processor 
uses a background thread with variable timing. Under CI load, 2 seconds isn't always enough.

## Your Task

Fix the test to wait for the **actual condition** (payment.status == "completed") 
rather than assuming a fixed duration.

## Running Tests Locally
