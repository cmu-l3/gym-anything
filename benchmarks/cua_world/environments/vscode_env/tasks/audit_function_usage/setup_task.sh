#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Audit Function Usage Task ==="

WORKSPACE_DIR="/home/ga/workspace/ecommerce_app"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{pricing,views,api,tests}

echo "Creating e-commerce application files..."

# Create pricing/calculator.py with the target function
cat > "$WORKSPACE_DIR/pricing/calculator.py" << 'EOF'
"""
Pricing calculator module for e-commerce platform
"""

def calculate_discount(price, customer_type):
    """
    Calculate discount based on customer type.
    
    Args:
        price: Original price
        customer_type: Type of customer ('regular', 'premium', 'vip')
    
    Returns:
        Discounted price
    """
    discounts = {
        'regular': 0.0,
        'premium': 0.10,
        'vip': 0.20
    }
    
    discount_rate = discounts.get(customer_type, 0.0)
    return price * (1 - discount_rate)


def calculate_tax(price, state):
    """Calculate sales tax based on state"""
    tax_rates = {
        'CA': 0.0725,
        'NY': 0.08,
        'TX': 0.0625
    }
    return price * tax_rates.get(state, 0.0)


def calculate_shipping(weight, zone):
    """Calculate shipping cost"""
    base_rate = 5.00
    return base_rate + (weight * 0.5) + (zone * 2.0)
EOF

# Create views/checkout.py
cat > "$WORKSPACE_DIR/views/checkout.py" << 'EOF'
"""
Checkout view handlers
"""
from pricing.calculator import calculate_discount, calculate_tax

def process_checkout(cart_total, customer, state):
    """Process checkout with discounts and tax"""
    # Apply customer discount
    discounted_price = calculate_discount(cart_total, customer.type)
    
    # Add tax
    tax = calculate_tax(discounted_price, state)
    final_price = discounted_price + tax
    
    return final_price


def get_checkout_summary(cart_total, customer, state):
    """Get checkout summary for display"""
    original = cart_total
    discounted = calculate_discount(cart_total, customer.type)
    tax = calculate_tax(discounted, state)
    
    return {
        'original': original,
        'discounted': discounted,
        'tax': tax,
        'total': discounted + tax
    }
EOF

# Create views/cart.py
cat > "$WORKSPACE_DIR/views/cart.py" << 'EOF'
"""
Shopping cart views
"""
from pricing.calculator import calculate_discount

def get_cart_summary(items, customer):
    """Get cart summary with discount preview"""
    subtotal = sum(item.price * item.quantity for item in items)
    
    # Show discount preview
    final_price = calculate_discount(subtotal, customer.type)
    savings = subtotal - final_price
    
    return {
        'subtotal': subtotal,
        'final_price': final_price,
        'savings': savings
    }


def update_cart_item(cart, item_id, quantity, customer):
    """Update cart item and recalculate totals"""
    cart.update_quantity(item_id, quantity)
    new_subtotal = cart.get_subtotal()
    
    # Recalculate with discount
    discounted = calculate_discount(new_subtotal, customer.type)
    
    return {
        'subtotal': new_subtotal,
        'discounted': discounted
    }
EOF

# Create api/discount_api.py
cat > "$WORKSPACE_DIR/api/discount_api.py" << 'EOF'
"""
REST API endpoints for discount calculations
"""
from flask import Flask, request, jsonify
from pricing.calculator import calculate_discount

app = Flask(__name__)

@app.route('/api/v1/discount', methods=['POST'])
def get_discount():
    """API endpoint to calculate discount"""
    data = request.json
    price = data.get('price')
    customer_type = data.get('customer_type')
    
    discounted = calculate_discount(price, customer_type)
    
    return jsonify({
        'original_price': price,
        'discounted_price': discounted,
        'savings': price - discounted
    })


@app.route('/api/v1/bulk-discount', methods=['POST'])
def get_bulk_discount():
    """Calculate discounts for multiple items"""
    data = request.json
    items = data.get('items', [])
    customer_type = data.get('customer_type')
    
    results = []
    for item in items:
        discounted = calculate_discount(item['price'], customer_type)
        results.append({
            'item_id': item['id'],
            'original': item['price'],
            'discounted': discounted
        })
    
    return jsonify({'items': results})
EOF

# Create tests/test_pricing.py
cat > "$WORKSPACE_DIR/tests/test_pricing.py" << 'EOF'
"""
Unit tests for pricing module
"""
import unittest
from pricing.calculator import calculate_discount

class TestPricing(unittest.TestCase):
    
    def test_regular_customer_no_discount(self):
        """Regular customers get no discount"""
        result = calculate_discount(100.0, 'regular')
        self.assertEqual(result, 100.0)
    
    def test_premium_customer_discount(self):
        """Premium customers get 10% discount"""
        result = calculate_discount(100.0, 'premium')
        self.assertEqual(result, 90.0)
    
    def test_vip_customer_discount(self):
        """VIP customers get 20% discount"""
        result = calculate_discount(100.0, 'vip')
        self.assertEqual(result, 80.0)
    
    def test_invalid_customer_type(self):
        """Invalid customer type returns no discount"""
        result = calculate_discount(100.0, 'unknown')
        self.assertEqual(result, 100.0)
    
    def test_zero_price(self):
        """Zero price edge case"""
        result = calculate_discount(0.0, 'premium')
        self.assertEqual(result, 0.0)


if __name__ == '__main__':
    unittest.main()
EOF

# Create README.md
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# E-Commerce Pricing Application

Simple pricing calculator for e-commerce platform with customer-based discounts.

## Structure
- `pricing/` - Core pricing logic with discount calculations
- `views/` - Web view handlers for checkout and cart
- `api/` - REST API endpoints for discount services
- `tests/` - Unit tests for pricing functions

## Key Functions
- `calculate_discount(price, customer_type)` - Main discount calculation function

## Customer Types
- `regular` - No discount (0%)
- `premium` - 10% discount
- `vip` - 20% discount

## Planned Refactoring
The `calculate_discount` function will be extended to support promotional codes as a third parameter.
EOF

# Create __init__ files
touch "$WORKSPACE_DIR/pricing/__init__.py"
touch "$WORKSPACE_DIR/views/__init__.py"
touch "$WORKSPACE_DIR/api/__init__.py"
touch "$WORKSPACE_DIR/tests/__init__.py"

# Initialize git repository
echo "Initializing Git repository..."
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit: e-commerce pricing system"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/pricing/calculator.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Audit Function Usage Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. In calculator.py, locate the calculate_discount function"
echo "  2. Right-click on 'calculate_discount' and select 'Find All References' (or press Shift+F12)"
echo "  3. Review all usage locations in the References panel"
echo "  4. Create a new file: REFACTOR_PLAN.md"
echo "  5. Document all usage locations with file paths and line numbers"
echo "  6. Add a refactoring comment above the function definition"
echo "  7. Save all changes (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Target function: calculate_discount in pricing/calculator.py"