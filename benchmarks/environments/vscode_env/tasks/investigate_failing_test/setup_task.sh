#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Investigate Failing Test Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_processor"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create main payment module with intentional bug
cat > "$WORKSPACE_DIR/payment.py" << 'EOF'
"""Payment processing module"""

def calculate_fee(amount, fee_percent=2.5):
    """Calculate transaction fee"""
    if amount < 0:
        raise ValueError("Amount cannot be negative")
    return amount * (fee_percent / 100)

def process_payment(amount, currency="USD"):
    """Process a payment transaction"""
    fee = calculate_fee(amount)
    total = amount + fee
    return {
        "amount": amount,
        "fee": fee,
        "total": total,
        "currency": currency,
        "status": "processed"
    }

def validate_card(card_number):
    """Basic card validation (Luhn algorithm not implemented)"""
    # Intentionally buggy: should check length properly
    if not card_number:
        return False
    # BUG: This returns True for any non-empty string, even wrong length
    return len(str(card_number)) >= 10
EOF

# Create test file with one failing test
cat > "$WORKSPACE_DIR/tests/test_payment.py" << 'EOF'
"""Test suite for payment processing"""
import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from payment import calculate_fee, process_payment, validate_card

def test_calculate_fee_positive():
    """Test fee calculation with positive amount"""
    fee = calculate_fee(100.0, 2.5)
    assert fee == 2.5

def test_calculate_fee_zero():
    """Test fee calculation with zero amount"""
    fee = calculate_fee(0, 2.5)
    assert fee == 0

def test_process_payment_basic():
    """Test basic payment processing"""
    result = process_payment(100.0)
    assert result["amount"] == 100.0
    assert result["fee"] == 2.5
    assert result["total"] == 102.5
    assert result["currency"] == "USD"

def test_validate_card_valid():
    """Test card validation with 16-digit number"""
    # This test will FAIL because validate_card is buggy
    # It should reject cards that aren't exactly 16 digits
    assert validate_card("4532015112830366") == True
    assert validate_card("12345") == False  # This will fail - bug accepts it!

def test_validate_card_empty():
    """Test card validation with empty input"""
    assert validate_card("") == False
    assert validate_card(None) == False

def test_negative_amount_raises_error():
    """Test that negative amounts raise ValueError"""
    with pytest.raises(ValueError):
        calculate_fee(-50)
EOF

# Create __init__.py for package
touch "$WORKSPACE_DIR/tests/__init__.py"

# Create pytest configuration
cat > "$WORKSPACE_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -v
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install pytest if not already installed
echo "Installing pytest..."
sudo -u ga pip install pytest >/dev/null 2>&1 || true

# Remove any existing pytest settings to force agent to discover testing
echo "Cleaning VSCode settings to ensure fresh testing setup..."
SETTINGS_DIR="/home/ga/.config/Code/User"
sudo -u ga mkdir -p "$SETTINGS_DIR"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

# Remove pytest-related settings using Python
sudo -u ga python3 << 'PYTHON'
import json
import os

settings_path = "/home/ga/.config/Code/User/settings.json"
try:
    if os.path.exists(settings_path):
        with open(settings_path, 'r') as f:
            settings = json.load(f)
    else:
        settings = {}
    
    # Remove any testing-related settings
    keys_to_remove = [
        "python.testing.pytestEnabled",
        "python.testing.unittestEnabled", 
        "python.testing.pytestArgs",
        "python.testing.cwd",
        "python.testing.autoTestDiscoverOnSaveEnabled"
    ]
    
    for key in keys_to_remove:
        settings.pop(key, None)
    
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    
    print("Cleaned testing settings")
except Exception as e:
    print(f"Note: {e}")
PYTHON

# Remove workspace-specific settings if they exist
WORKSPACE_SETTINGS="$WORKSPACE_DIR/.vscode"
if [ -d "$WORKSPACE_SETTINGS" ]; then
    sudo rm -rf "$WORKSPACE_SETTINGS"
fi

# Open VSCode to the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Give VSCode time to load workspace
sleep 3

echo "=== Investigate Failing Test Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. VSCode is open with the payment_processor project"
echo "  2. Configure VSCode Test Explorer to use pytest"
echo "  3. Run tests using the integrated Test Explorer UI"
echo "  4. Identify which test(s) are failing"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Files: payment.py, tests/test_payment.py, pytest.ini"