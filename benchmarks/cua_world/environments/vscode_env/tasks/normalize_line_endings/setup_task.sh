#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Normalize Line Endings Task ==="

# Install dos2unix and unix2dos if not present
if ! command -v unix2dos &> /dev/null; then
    echo "Installing dos2unix package..."
    apt-get update -qq
    apt-get install -y dos2unix > /dev/null 2>&1
fi

WORKSPACE_DIR="/home/ga/workspace/payment-service"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{src,tests,scripts,docs,config}

# Create Python files with CRLF endings
cat << 'EOF' > "$WORKSPACE_DIR/src/api.py"
"""Payment API module"""

def process_payment(amount, currency):
    """Process a payment transaction"""
    if amount <= 0:
        raise ValueError("Amount must be positive")
    return {"status": "success", "amount": amount, "currency": currency}

def refund_payment(transaction_id):
    """Refund a payment"""
    return {"status": "refunded", "transaction_id": transaction_id}
EOF
unix2dos "$WORKSPACE_DIR/src/api.py" 2>/dev/null

cat << 'EOF' > "$WORKSPACE_DIR/src/models.py"
"""Data models for payment service"""

class Payment:
    def __init__(self, amount, currency, user_id):
        self.amount = amount
        self.currency = currency
        self.user_id = user_id
    
    def validate(self):
        return self.amount > 0 and len(self.currency) == 3
EOF
unix2dos "$WORKSPACE_DIR/src/models.py" 2>/dev/null

# Create JavaScript file with CRLF
cat << 'EOF' > "$WORKSPACE_DIR/src/utils.js"
// Utility functions for payment processing

function formatCurrency(amount, currency) {
    return `${currency} ${amount.toFixed(2)}`;
}

function validateCard(cardNumber) {
    return cardNumber.length === 16;
}

module.exports = { formatCurrency, validateCard };
EOF
unix2dos "$WORKSPACE_DIR/src/utils.js" 2>/dev/null

# Create test file with CRLF
cat << 'EOF' > "$WORKSPACE_DIR/tests/test_api.py"
"""Tests for payment API"""
import unittest
from src.api import process_payment, refund_payment

class TestPaymentAPI(unittest.TestCase):
    def test_process_payment(self):
        result = process_payment(100, "USD")
        self.assertEqual(result["status"], "success")
    
    def test_refund_payment(self):
        result = refund_payment("txn_123")
        self.assertEqual(result["status"], "refunded")
EOF
unix2dos "$WORKSPACE_DIR/tests/test_api.py" 2>/dev/null

# Create shell script with CRLF (this will be BROKEN on Linux)
cat << 'EOF' > "$WORKSPACE_DIR/scripts/deploy.sh"
#!/bin/bash
# Deployment script for payment service

echo "Starting deployment..."
python -m pytest tests/
echo "Tests passed!"
echo "Deploying to production..."
EOF
unix2dos "$WORKSPACE_DIR/scripts/deploy.sh" 2>/dev/null
chmod +x "$WORKSPACE_DIR/scripts/deploy.sh"

# Create README with CRLF
cat << 'EOF' > "$WORKSPACE_DIR/docs/README.md"
# Payment Service

A robust payment processing service.

## Features
- Process payments
- Handle refunds
- Multi-currency support

## Setup
Run `./scripts/deploy.sh` to deploy.
EOF
unix2dos "$WORKSPACE_DIR/docs/README.md" 2>/dev/null

# Create config file with CRLF
cat << 'EOF' > "$WORKSPACE_DIR/config/settings.json"
{
  "environment": "development",
  "database": {
    "host": "localhost",
    "port": 5432
  },
  "payment": {
    "timeout": 30,
    "retry_count": 3
  }
}
EOF
unix2dos "$WORKSPACE_DIR/config/settings.json" 2>/dev/null

# Create a binary file (should NOT be converted)
if [ -f /usr/share/pixmaps/debian-logo.png ]; then
    cp /usr/share/pixmaps/debian-logo.png "$WORKSPACE_DIR/logo.png"
else
    # Create a small binary file if debian logo not found
    echo -en '\x89\x50\x4E\x47\x0D\x0A\x1A\x0A' > "$WORKSPACE_DIR/logo.png"
fi

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "Test User"
sudo -u ga git config user.email "test@example.com"

# Add all files with CRLF and commit
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with CRLF endings"

# Configure git to treat files with LF locally (simulates Linux behavior)
# This makes Git think all files are modified due to line ending differences
sudo -u ga git config core.autocrlf input

# Touch files to trigger git to detect CRLF->LF conversion needed
# This simulates the state after cloning on Linux
cd "$WORKSPACE_DIR"
echo "" >> "$WORKSPACE_DIR/src/api.py"
sudo -u ga git checkout -- "$WORKSPACE_DIR/src/api.py"

echo "=== Verifying setup: Git should show files as modified ==="
cd "$WORKSPACE_DIR"
sudo -u ga git status --short

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Normalize Line Endings Task Setup Complete ==="
echo "📝 Problem:"
echo "   - All files have CRLF (Windows) line endings"
echo "   - Git shows all files as modified (run 'git status' to see)"
echo "   - scripts/deploy.sh won't execute due to CRLF"
echo ""
echo "📝 Your Tasks:"
echo "   1. Configure VSCode workspace: .vscode/settings.json with 'files.eol': 'lf'"
echo "   2. Convert all text files from CRLF to LF"
echo "   3. Create .gitattributes with line ending rules"
echo "   4. Verify git status shows minimal changes"
echo ""
echo "💡 Hints:"
echo "   - Check VSCode status bar for line ending indicator (CRLF/LF)"
echo "   - Use Command Palette: 'Change End of Line Sequence'"
echo "   - Don't modify binary file logo.png"