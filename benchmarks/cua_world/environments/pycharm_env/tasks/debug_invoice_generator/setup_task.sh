#!/bin/bash
echo "=== Setting up debug_invoice_generator task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/invoice_renderer"
mkdir -p "$PROJECT_DIR/src"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/invoices"

# Clean up any previous run artifacts
rm -f /tmp/debug_invoice_result.json
rm -f /tmp/task_start_time.txt
date +%s > /tmp/task_start_time.txt

# --- 1. Create Source Files ---

# requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
reportlab>=4.0.0
pytest>=7.0.0
EOF

# src/models.py
cat > "$PROJECT_DIR/src/models.py" << 'EOF'
from dataclasses import dataclass
from typing import List

@dataclass
class Item:
    description: str
    sku: str
    unit_price: float
    quantity: int

@dataclass
class Customer:
    name: str
    address: str
    email: str
    credit_card: str  # Raw PAN

@dataclass
class Order:
    order_id: str
    customer: Customer
    items: List[Item]
    tax_rate: float = 0.08
EOF

# src/utils.py (Contains BUG 1 and BUG 2)
cat > "$PROJECT_DIR/src/utils.py" << 'EOF'
"""Utility functions for invoice calculations and formatting."""

# BUG 1: Using float for currency causes precision errors
# Should import and use decimal.Decimal
def calculate_line_total(price: float, quantity: int) -> float:
    """Calculate total price for a line item."""
    return price * quantity

def calculate_subtotal(items: list) -> float:
    """Sum up all line items."""
    total = 0.0
    for item in items:
        total += calculate_line_total(item.unit_price, item.quantity)
    return total

def calculate_tax(subtotal: float, rate: float) -> float:
    """Calculate tax amount."""
    return subtotal * rate

def calculate_grand_total(subtotal: float, tax: float) -> float:
    """Calculate final total."""
    return subtotal + tax

def format_currency(amount: float) -> str:
    """Format number as currency string."""
    return f"${amount:,.2f}"

# BUG 2: Returns full credit card number instead of masking it
def mask_credit_card(cc_number: str) -> str:
    """
    Mask credit card number for PCI compliance.
    Should show only last 4 digits (e.g., ****-****-****-1234).
    """
    # Security Violation: Returning full PAN!
    return cc_number
EOF

# src/generator.py (Contains BUG 3)
cat > "$PROJECT_DIR/src/generator.py" << 'EOF'
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter
from src.utils import calculate_line_total, calculate_subtotal, calculate_tax, calculate_grand_total, format_currency, mask_credit_card

class InvoiceGenerator:
    def __init__(self, output_path: str):
        self.c = canvas.Canvas(output_path, pagesize=letter)
        self.width, self.height = letter
        self.y = self.height - 50  # Start 50px from top
        self.left_margin = 50
        self.bottom_margin = 50

    def draw_header(self, order):
        self.c.setFont("Helvetica-Bold", 16)
        self.c.drawString(self.left_margin, self.y, f"INVOICE #{order.order_id}")
        self.y -= 30
        
        self.c.setFont("Helvetica", 12)
        self.c.drawString(self.left_margin, self.y, f"Bill To: {order.customer.name}")
        self.y -= 20
        # Uses the buggy mask function
        cc_masked = mask_credit_card(order.customer.credit_card)
        self.c.drawString(self.left_margin, self.y, f"Payment Method: {cc_masked}")
        self.y -= 40

    def draw_items(self, items):
        self.c.setFont("Helvetica-Bold", 10)
        self.c.drawString(self.left_margin, self.y, "Description")
        self.c.drawString(self.left_margin + 300, self.y, "Qty")
        self.c.drawString(self.left_margin + 350, self.y, "Price")
        self.c.drawString(self.left_margin + 450, self.y, "Total")
        self.y -= 20
        self.c.setFont("Helvetica", 10)

        for item in items:
            # BUG 3: Page break logic is wrong.
            # Checks if y is below absolute zero, not the bottom margin.
            # Footer text effectively overwrites items if list is long.
            if self.y < 0:
                self.c.showPage()
                self.y = self.height - 50
                self.c.setFont("Helvetica", 10)

            total = calculate_line_total(item.unit_price, item.quantity)
            
            self.c.drawString(self.left_margin, self.y, item.description[:50])
            self.c.drawString(self.left_margin + 300, self.y, str(item.quantity))
            self.c.drawString(self.left_margin + 350, self.y, format_currency(item.unit_price))
            self.c.drawString(self.left_margin + 450, self.y, format_currency(total))
            self.y -= 15

    def generate(self, order):
        self.draw_header(order)
        self.draw_items(order.items)
        
        # Draw totals
        subtotal = calculate_subtotal(order.items)
        tax = calculate_tax(subtotal, order.tax_rate)
        grand_total = calculate_grand_total(subtotal, tax)
        
        self.y -= 20
        self.c.drawString(self.left_margin + 350, self.y, "Subtotal:")
        self.c.drawString(self.left_margin + 450, self.y, format_currency(subtotal))
        self.y -= 15
        self.c.drawString(self.left_margin + 350, self.y, "Tax:")
        self.c.drawString(self.left_margin + 450, self.y, format_currency(tax))
        self.y -= 15
        self.c.setFont("Helvetica-Bold", 12)
        self.c.drawString(self.left_margin + 350, self.y, "Total:")
        self.c.drawString(self.left_margin + 450, self.y, format_currency(grand_total))
        
        self.c.save()
EOF

# src/__init__.py
touch "$PROJECT_DIR/src/__init__.py"

# --- 2. Create Tests ---

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
from src.models import Item, Customer, Order

@pytest.fixture
def sample_order():
    items = [
        Item("Widget", "SKU1", 19.99, 1),
        Item("Gadget", "SKU2", 29.99, 2)
    ]
    customer = Customer("John Doe", "123 Main St", "john@example.com", "4111222233334444")
    return Order("ORD-001", customer, items)
EOF

# tests/test_math.py
cat > "$PROJECT_DIR/tests/test_math.py" << 'EOF'
from src.utils import calculate_line_total, calculate_subtotal, calculate_tax, calculate_grand_total
from src.models import Item
# We check if Decimal is being used implicitly by checking precision
from decimal import Decimal

def test_calculate_line_total_precision():
    # 19.99 * 3 = 59.97 exactly
    # Float math often gives 59.970000000000006
    result = calculate_line_total(19.99, 3)
    # Convert to string to check for trailing floating point garbage
    assert str(result) == "59.97", "Floating point error detected! Use Decimal."

def test_subtotal_precision():
    # Summing many floats often drifts
    items = [Item("X", "Y", 0.1, 1) for _ in range(10)]
    # 0.1 * 10 should be 1.0, float often 0.9999999999 or 1.00000001
    result = calculate_subtotal(items)
    assert str(result) == "1.0", f"Precision error: {result}"

def test_tax_calculation():
    # 100 * 0.08 = 8.00
    assert float(calculate_tax(100.00, 0.08)) == 8.00

def test_grand_total():
    assert float(calculate_grand_total(100.00, 8.00)) == 108.00
EOF

# tests/test_privacy.py
cat > "$PROJECT_DIR/tests/test_privacy.py" << 'EOF'
from src.utils import mask_credit_card

def test_mask_credit_card_hides_digits():
    cc = "1234567812345678"
    masked = mask_credit_card(cc)
    assert "12345678" not in masked, "Original middle digits exposed!"

def test_mask_credit_card_shows_last_four():
    cc = "1111222233334444"
    masked = mask_credit_card(cc)
    assert masked.endswith("4444"), "Last four digits should be visible"

def test_mask_credit_card_format():
    # Typical format: ****-****-****-1234 or ************1234
    cc = "4111222233334444"
    masked = mask_credit_card(cc)
    assert masked.count("*") >= 12, "Not enough masking characters"

def test_mask_short_input():
    # Handle edge case gently
    assert mask_credit_card("1234") == "1234"
EOF

# tests/test_layout.py
cat > "$PROJECT_DIR/tests/test_layout.py" << 'EOF'
from unittest.mock import MagicMock
from src.generator import InvoiceGenerator
from src.models import Order, Customer, Item

def test_page_break_trigger():
    # Setup generator
    gen = InvoiceGenerator("dummy.pdf")
    gen.c = MagicMock()
    
    # Mock height to be small to force page break
    gen.height = 200
    # Start y at 100
    gen.y = 100
    # Bottom margin is 50
    
    # Create enough items to go below y=50
    # Each item takes 15px.
    # 100 (start) - 50 (margin) = 50px printable space
    # 50 / 15 = ~3 items fits. 10 items should force break.
    items = [Item(f"Item {i}", "SKU", 10.0, 1) for i in range(10)]
    
    gen.draw_items(items)
    
    # Check if showPage was called
    assert gen.c.showPage.called, "Page break was not triggered!"

def test_margin_respect():
    gen = InvoiceGenerator("dummy.pdf")
    gen.c = MagicMock()
    gen.height = 500
    gen.y = 100
    
    # Add items
    items = [Item("Item", "SKU", 10, 1) for _ in range(5)]
    
    # Capture the y coordinates where text was drawn
    y_coords = []
    def mock_drawString(x, y, text):
        y_coords.append(y)
    gen.c.drawString.side_effect = mock_drawString
    
    gen.draw_items(items)
    
    # Ensure no text was drawn below bottom margin (50)
    # Note: If page break works, y resets to top. If fails, y goes 40, 25, 10...
    violations = [y for y in y_coords if y < 50]
    assert not violations, f"Drew text below bottom margin at y={violations}"
    
def test_header_position():
    gen = InvoiceGenerator("dummy.pdf")
    assert gen.y == gen.height - 50

def test_reset_position_after_break():
    gen = InvoiceGenerator("dummy.pdf")
    gen.c = MagicMock()
    gen.y = -10 # Force break condition if logic were y < 0 (buggy) vs y < margin
    
    # Manually trigger check logic if we were simulating the loop
    # Ideally this tests the logic inside draw_items
    pass 
EOF

# --- 3. Environment Setup ---

# Install deps
pip3 install reportlab pytest > /dev/null 2>&1

# Setup PyCharm Project
su - ga -c "mkdir -p $PROJECT_DIR/.idea"
# (Skipping complex XML injection for brevity, standard PyCharm opening works)

# Open PyCharm
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 nohup /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"

# Wait for PyCharm to load
echo "Waiting for PyCharm..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -q "invoice_renderer"; then
        echo "PyCharm window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "invoice_renderer" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="