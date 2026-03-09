#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Annotate for Stakeholder Task ==="

WORKSPACE_DIR="/home/ga/workspace/pricing_service"
TASK_DIR="/workspace/tasks/annotate_for_stakeholder"

# Create project structure
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# Create assets directory if it doesn't exist
mkdir -p "$TASK_DIR/assets"

# Create pricing.py (the file to be annotated)
cat > "$TASK_DIR/assets/pricing.py" << 'EOF'
from decimal import Decimal
from typing import Optional
from models import Subscription, CustomerTier

MINIMUM_PRICE = Decimal("99.00")
ENTERPRISE_DISCOUNT = Decimal("0.20")
ANNUAL_DISCOUNT = Decimal("0.15")

def calculate_subscription_price(
    base_price: Decimal,
    customer_tier: CustomerTier,
    billing_cycle: str,
    promotional_code: Optional[str] = None
) -> Decimal:
    """Calculate final subscription price with applicable discounts."""
    
    price = base_price
    
    if customer_tier == CustomerTier.ENTERPRISE:
        price = price * (Decimal("1") - ENTERPRISE_DISCOUNT)
    
    if billing_cycle.lower() == "annual":
        price = price * (Decimal("1") - ANNUAL_DISCOUNT)
    
    if promotional_code:
        promo_discount = _validate_and_get_promo_discount(promotional_code)
        if promo_discount:
            price = price * (Decimal("1") - promo_discount)
    
    return max(price, MINIMUM_PRICE)


def _validate_and_get_promo_discount(code: str) -> Optional[Decimal]:
    """Validate promo code and return discount if valid."""
    return None
EOF

# Create models.py
cat > "$TASK_DIR/assets/models.py" << 'EOF'
from enum import Enum
from dataclasses import dataclass
from decimal import Decimal

class CustomerTier(Enum):
    FREE = "free"
    PRO = "pro"
    ENTERPRISE = "enterprise"

@dataclass
class Subscription:
    tier: CustomerTier
    billing_cycle: str
    base_price: Decimal
EOF

# Create test_pricing.py
cat > "$TASK_DIR/assets/test_pricing.py" << 'EOF'
import pytest
from decimal import Decimal
import sys
sys.path.insert(0, '/home/ga/workspace/pricing_service/src')

from pricing import calculate_subscription_price
from models import CustomerTier

def test_enterprise_discount():
    """Enterprise customers get 20% off."""
    price = calculate_subscription_price(
        base_price=Decimal("200.00"),
        customer_tier=CustomerTier.ENTERPRISE,
        billing_cycle="monthly"
    )
    assert price == Decimal("160.00")

def test_annual_discount():
    """Annual billing gets 15% off."""
    price = calculate_subscription_price(
        base_price=Decimal("200.00"),
        customer_tier=CustomerTier.PRO,
        billing_cycle="annual"
    )
    assert price == Decimal("170.00")

def test_combined_discounts():
    """Enterprise + Annual = both discounts applied."""
    price = calculate_subscription_price(
        base_price=Decimal("200.00"),
        customer_tier=CustomerTier.ENTERPRISE,
        billing_cycle="annual"
    )
    assert price == Decimal("136.00")

def test_minimum_price_floor():
    """Price never goes below $99."""
    price = calculate_subscription_price(
        base_price=Decimal("100.00"),
        customer_tier=CustomerTier.ENTERPRISE,
        billing_cycle="annual"
    )
    assert price == Decimal("99.00")
EOF

# Create requirements.txt
cat > "$TASK_DIR/assets/requirements.txt" << 'EOF'
pytest==7.4.3
EOF

# Create README.md
cat > "$TASK_DIR/assets/README.md" << 'EOF'
# Pricing Service

Subscription pricing calculation for SaaS product.

## Business Rules
- Base pricing varies by plan tier
- Enterprise customers receive volume discounts
- Annual commitments receive billing cycle discounts
- Minimum price floor ensures profitability
EOF

# Copy files to workspace
sudo -u ga cp "$TASK_DIR/assets/pricing.py" "$WORKSPACE_DIR/src/pricing.py"
sudo -u ga cp "$TASK_DIR/assets/models.py" "$WORKSPACE_DIR/src/models.py"
sudo -u ga cp "$TASK_DIR/assets/test_pricing.py" "$WORKSPACE_DIR/tests/test_pricing.py"
sudo -u ga cp "$TASK_DIR/assets/requirements.txt" "$WORKSPACE_DIR/requirements.txt"
sudo -u ga cp "$TASK_DIR/assets/README.md" "$WORKSPACE_DIR/README.md"

# Create __init__.py files
sudo -u ga touch "$WORKSPACE_DIR/src/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/tests/__init__.py"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "Project structure created at $WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2

# Open the specific file
echo "Opening pricing.py..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/src/pricing.py'" &
sleep 3

# Focus VSCode window
focus_vscode_window

# Navigate to the calculate_subscription_price function (around line 10)
echo "Navigating to function..."
export DISPLAY=:1
su - ga -c "DISPLAY=:1 xdotool search --name 'Visual Studio Code' windowactivate --sync" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key ctrl+g" || true  # Go to line
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type '10'" || true
sleep 0.3
su - ga -c "DISPLAY=:1 xdotool key Return" || true
sleep 0.5

echo "=== Annotate for Stakeholder Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review the calculate_subscription_price function"
echo "  2. Add business-focused comments explaining:"
echo "     - Enterprise customers get 20% discount"
echo "     - Annual billing gets 15% discount"
echo "     - Minimum price is \$99"
echo "  3. Use simple, non-technical language"
echo "  4. Add at least 4 meaningful comments"
echo "  5. Save the file (Ctrl+S)"