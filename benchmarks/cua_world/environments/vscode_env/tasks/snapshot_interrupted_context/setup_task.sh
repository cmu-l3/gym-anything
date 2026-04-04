#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Snapshot Interrupted Context Task ==="

WORKSPACE_DIR="/home/ga/workspace"
PROJECT_A="$WORKSPACE_DIR/project_alpha"
PROJECT_B="$WORKSPACE_DIR/project_beta"

# Clean up any existing projects
sudo rm -rf "$PROJECT_A" "$PROJECT_B" 2>/dev/null || true

# Create project_alpha (Python FastAPI app)
echo "Creating project_alpha structure..."
sudo -u ga mkdir -p "$PROJECT_A/services"
sudo -u ga mkdir -p "$PROJECT_A/tests"

# Create buggy payment processor file
cat > "$PROJECT_A/services/__init__.py" << 'EOF'
"""Payment services package"""
EOF

cat > "$PROJECT_A/services/payment_processor.py" << 'EOF'
"""Payment processing service"""
import logging
from datetime import datetime
from decimal import Decimal

logger = logging.getLogger(__name__)

class PaymentProcessor:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.last_transaction_id = None
    
    def process_payment(self, amount: float, currency: str, customer_id: str):
        """Process a payment transaction"""
        logger.info(f"Processing payment: {amount} {currency} for {customer_id}")
        
        # Validate amount
        if amount <= 0:
            raise ValueError("Amount must be positive")
        
        # BUG: Using float instead of Decimal causes precision issues
        # When amount is 10.10, it gets stored as 10.099999999
        transaction_data = {
            "amount": amount,
            "currency": currency,
            "customer_id": customer_id,
            "timestamp": datetime.utcnow().isoformat(),
            "processed": False
        }
        
        # Simulate API call
        self.last_transaction_id = f"txn_{customer_id}_{int(amount*100)}"
        transaction_data["processed"] = True
        
        logger.info(f"Transaction completed: {self.last_transaction_id}")
        return transaction_data
    
    def verify_transaction(self, transaction_id: str) -> bool:
        """Verify a transaction was processed"""
        return self.last_transaction_id == transaction_id

    def refund_payment(self, transaction_id: str, amount: float):
        """Issue a refund"""
        # BUG: Same float precision issue here
        logger.info(f"Refunding {amount} for transaction {transaction_id}")
        return {"refunded": True, "amount": amount}
EOF

# Create a test file to give context
cat > "$PROJECT_A/tests/__init__.py" << 'EOF'
"""Tests package"""
EOF

cat > "$PROJECT_A/tests/test_payment.py" << 'EOF'
"""Test payment processing"""
import pytest
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from services.payment_processor import PaymentProcessor

def test_payment_amounts():
    """Test that payment amounts are stored correctly"""
    processor = PaymentProcessor("test_key_123")
    
    # This test is failing - amounts don't match!
    result = processor.process_payment(10.10, "USD", "cust_123")
    
    # Expected: 10.10, Actual: 10.099999999
    assert result["amount"] == 10.10, f"Amount mismatch: {result['amount']}"

def test_refund():
    """Test refund processing"""
    processor = PaymentProcessor("test_key_123")
    result = processor.refund_payment("txn_123", 5.50)
    assert result["refunded"] == True
EOF

# Create requirements file
cat > "$PROJECT_A/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
pytest==7.4.3
EOF

# Create README explaining the scenario
cat > "$PROJECT_A/README.md" << 'EOF'
# Project Alpha - Payment Processing Service

## Current Status: DEBUGGING IN PROGRESS

You've been investigating a bug where payment amounts are stored incorrectly.
Customers report charges of $10.10 appear as $10.09 in receipts.

### Investigation so far:
- Identified the issue is in `services/payment_processor.py`
- Test in `tests/test_payment.py` is failing
- Suspect it's related to floating point precision
- Line 26 looks suspicious (using float directly)

### Next steps:
- Need to test changing float to Decimal
- May need to refactor refund_payment() as well
- Should check database schema

**STATUS: YOU WERE ABOUT TO TEST A FIX WHEN INTERRUPTED**
EOF

# Create project_beta (placeholder for context)
echo "Creating project_beta structure..."
sudo -u ga mkdir -p "$PROJECT_B/src"
cat > "$PROJECT_B/src/App.jsx" << 'EOF'
// Production broken dashboard (placeholder for context)
import React from 'react';

function App() {
  // Login broken - needs immediate fix
  return <div>Dashboard</div>;
}

export default App;
EOF

cat > "$PROJECT_B/README.md" << 'EOF'
# Project Beta - React Dashboard

🚨 URGENT: Production login is broken!
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with project_alpha and relevant files
echo "Opening VSCode with project_alpha..."
su - ga -c "DISPLAY=:1 code '$PROJECT_A' --new-window" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

focus_vscode_window
sleep 2

# Open the key files in tabs
echo "Opening files in VSCode..."
su - ga -c "DISPLAY=:1 code '$PROJECT_A/services/payment_processor.py'" || true
sleep 1
su - ga -c "DISPLAY=:1 code '$PROJECT_A/tests/test_payment.py'" || true
sleep 1
su - ga -c "DISPLAY=:1 code '$PROJECT_A/README.md'" || true
sleep 2

# Focus on payment_processor.py and position cursor near line 26
focus_vscode_window
sleep 1

# Use Ctrl+G to go to line 26 (the bug line)
echo "Navigating to line 26..."
su - ga -c "DISPLAY=:1 xdotool key --delay 150 ctrl+g" || true
sleep 1
su - ga -c "DISPLAY=:1 xdotool type --delay 80 '26'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 1

echo "=== Snapshot Interrupted Context Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "  You are debugging a payment processing bug in project_alpha."
echo "  You've identified the suspicious code at line 26 in payment_processor.py"
echo "  (using float instead of Decimal causes precision issues)."
echo ""
echo "  🚨 URGENT INTERRUPTION:"
echo "  Client B's production dashboard is broken - users cannot log in!"
echo "  You must switch to project_beta immediately."
echo ""
echo "📋 YOUR TASK:"
echo "  Create a context snapshot so you can resume debugging later:"
echo "  1. Add inline comment at line 26 with your investigation notes"
echo "  2. Add TODO marker at top of file summarizing debugging state"
echo "  3. Create _DEBUG_NOTES.md with timestamp, hypothesis, next steps"
echo "  4. Save workspace as 'project_alpha_debug_session.code-workspace'"
echo ""
echo "Files open: payment_processor.py (line 26), test_payment.py, README.md"