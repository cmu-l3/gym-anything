#!/bin/bash
echo "=== Setting up fix_ecommerce_scraper task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_ecommerce_scraper"
PROJECT_DIR="/home/ga/PycharmProjects/shop_scraper"

# 1. Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

# 2. Create Project Structure
mkdir -p "$PROJECT_DIR/scraper"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# 3. Create Virtual Environment and Install Dependencies
# We use the system python for simplicity in this environment, or create a venv
# creating requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQUIREMENTS'
beautifulsoup4>=4.12.0
pytest>=7.0
REQUIREMENTS

# 4. Create Data Files (The HTML snapshots)

# Legacy HTML (What the broken scraper expects)
cat > "$PROJECT_DIR/data/legacy_product.html" << 'HTML'
<!DOCTYPE html>
<html>
<body>
    <div class="product-container">
        <h1 class="product-title">Super Gadget X2000</h1>
        <div class="product-info">
            <span class="price">$999.99</span>
            <span class="stock-status">In Stock</span>
        </div>
        <div class="description">
            <table class="specs-table">
                <tr><td>Brand</td><td>TechCorp</td></tr>
                <tr><td>Model</td><td>X2000</td></tr>
                <tr><td>Weight</td><td>1.5kg</td></tr>
            </table>
        </div>
    </div>
</body>
</html>
HTML

# Modern HTML (The target structure - React style)
cat > "$PROJECT_DIR/data/modern_product.html" << 'HTML'
<!DOCTYPE html>
<html lang="en">
<body>
    <div id="root">
        <header class="site-header">...</header>
        <main class="pdp-layout">
            <div class="gallery-section">...</div>
            <div class="details-section">
                <!-- Title uses data-testid now -->
                <h1 data-testid="product-name" class="typography-h1">Super Gadget X2000</h1>
                
                <div class="pricing-widget">
                    <!-- Price is split for styling -->
                    <div class="current-price" aria-label="999.99 dollars">
                        <span class="currency-symbol">$</span>
                        <span class="integer-part">999</span>
                        <span class="fraction-part">.99</span>
                    </div>
                </div>

                <div class="inventory-widget">
                    <!-- Status is class-based now -->
                    <div class="status-indicator status-available" data-inventory-sku="12345">
                        <span class="icon"></span>
                        <span class="label">Ready to ship</span>
                    </div>
                </div>

                <div class="specifications-section">
                    <h3>Tech Specs</h3>
                    <!-- Table replaced by Definition List grid -->
                    <dl class="specs-grid">
                        <div class="spec-row">
                            <dt class="spec-term">Brand</dt>
                            <dd class="spec-def">TechCorp</dd>
                        </div>
                        <div class="spec-row">
                            <dt class="spec-term">Model</dt>
                            <dd class="spec-def">X2000</dd>
                        </div>
                        <div class="spec-row">
                            <dt class="spec-term">Weight</dt>
                            <dd class="spec-def">1.5kg</dd>
                        </div>
                    </dl>
                </div>
            </div>
        </main>
    </div>
</body>
</html>
HTML

# 5. Create Source Code (Broken implementation)

# scraper/__init__.py
touch "$PROJECT_DIR/scraper/__init__.py"

# scraper/utils.py (Helper functions - correct but need correct inputs)
cat > "$PROJECT_DIR/scraper/utils.py" << 'PY'
import re

def clean_text(text: str) -> str:
    """Removes whitespace and newlines."""
    if not text:
        return ""
    return " ".join(text.split())

def parse_price_string(price_str: str) -> float:
    """Converts '$999.99' to 999.99."""
    if not price_str:
        return 0.0
    # Remove currency symbols and commas
    clean = re.sub(r'[^\d.]', '', price_str)
    try:
        return float(clean)
    except ValueError:
        return 0.0
PY

# scraper/parsers.py (BROKEN - targets legacy HTML)
cat > "$PROJECT_DIR/scraper/parsers.py" << 'PY'
from bs4 import BeautifulSoup
from typing import Dict, Optional, Any
from scraper.utils import clean_text, parse_price_string

class ProductParser:
    def __init__(self, html_content: str):
        self.soup = BeautifulSoup(html_content, 'html.parser')

    def extract_title(self) -> Optional[str]:
        """Extract product title."""
        # LEGACY SELECTOR: .product-title
        tag = self.soup.find(class_="product-title")
        if tag:
            return clean_text(tag.text)
        return None

    def extract_price(self) -> float:
        """Extract product price."""
        # LEGACY SELECTOR: span.price
        tag = self.soup.find("span", class_="price")
        if tag:
            return parse_price_string(tag.text)
        return 0.0

    def extract_availability(self) -> bool:
        """Return True if in stock, False otherwise."""
        # LEGACY LOGIC: Check for text "In Stock"
        tag = self.soup.find(class_="stock-status")
        if tag and "in stock" in tag.text.lower():
            return True
        return False

    def extract_specs(self) -> Dict[str, str]:
        """Extract specifications as key-value pairs."""
        # LEGACY SELECTOR: table.specs-table
        specs = {}
        table = self.soup.find("table", class_="specs-table")
        if table:
            for row in table.find_all("tr"):
                cols = row.find_all("td")
                if len(cols) == 2:
                    key = clean_text(cols[0].text)
                    val = clean_text(cols[1].text)
                    specs[key] = val
        return specs
PY

# 6. Create Test Suite (Targets MODERN HTML - ensures failure initially)

cat > "$PROJECT_DIR/tests/test_parsers.py" << 'PY'
import pytest
import os
from scraper.parsers import ProductParser

# Load the modern HTML file
DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'data')
with open(os.path.join(DATA_DIR, 'modern_product.html'), 'r') as f:
    MODERN_HTML = f.read()

@pytest.fixture
def parser():
    return ProductParser(MODERN_HTML)

def test_extract_title(parser):
    """Should extract title from data-testid='product-name'."""
    title = parser.extract_title()
    assert title == "Super Gadget X2000", "Failed to extract title from modern HTML"

def test_extract_price(parser):
    """Should extract price from nested structure."""
    price = parser.extract_price()
    assert price == 999.99, f"Expected 999.99, got {price}"

def test_extract_availability(parser):
    """Should detect availability via class name."""
    is_available = parser.extract_availability()
    assert is_available is True, "Should be available based on status-available class"

def test_extract_specs(parser):
    """Should parse specs from dl/dt/dd grid."""
    specs = parser.extract_specs()
    assert specs.get("Brand") == "TechCorp"
    assert specs.get("Model") == "X2000"
    assert specs.get("Weight") == "1.5kg"

# --- Parameterized Tests with Synthetic Data (Anti-Gaming) ---
# These ensure the agent writes robust selectors, not just hardcoded values

@pytest.mark.parametrize("html_snippet,expected", [
    ('<h1 data-testid="product-name">Test Item 1</h1>', "Test Item 1"),
    ('<h1 class="typography-h1" data-testid="product-name">  Item  2  </h1>', "Item 2"),
])
def test_title_selector_robustness(html_snippet, expected):
    p = ProductParser(html_snippet)
    assert p.extract_title() == expected

@pytest.mark.parametrize("html_snippet,expected", [
    ('<div class="current-price"><span class="integer-part">10</span><span class="fraction-part">.50</span></div>', 10.50),
    ('<div class="current-price">$<span class="integer-part">1,200</span><span class="fraction-part">.00</span></div>', 1200.0),
])
def test_price_selector_robustness(html_snippet, expected):
    p = ProductParser(html_snippet)
    assert p.extract_price() == expected

@pytest.mark.parametrize("html_snippet,expected", [
    ('<div class="status-indicator status-available"></div>', True),
    ('<div class="status-indicator status-out-of-stock"></div>', False),
    ('<div class="status-indicator status-backorder"></div>', False), # Assuming strictly "available" is True
])
def test_availability_selector_robustness(html_snippet, expected):
    p = ProductParser(html_snippet)
    assert p.extract_availability() == expected

def test_specs_grid_structure():
    html = '''
    <dl class="specs-grid">
        <div class="spec-row"><dt>Color</dt><dd>Red</dd></div>
        <div class="spec-row"><dt>Size</dt><dd>Large</dd></div>
    </dl>
    '''
    p = ProductParser(html)
    specs = p.extract_specs()
    assert specs == {"Color": "Red", "Size": "Large"}
PY

# 7. Final Setup Steps
echo "$(date +%s)" > /tmp/${TASK_NAME}_start_ts

# Install requirements (if pip is available/needed, otherwise assume env is ready)
# In this env, bs4 and pytest are pre-installed or installable
pip3 install -r "$PROJECT_DIR/requirements.txt" > /dev/null 2>&1 || true

# Open PyCharm to the project
echo "Launching PyCharm..."
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"

# Wait for PyCharm
sleep 10
wait_for_project_loaded "shop_scraper" 120
dismiss_dialogs 5
focus_pycharm_window

# Take initial screenshot
take_screenshot /tmp/${TASK_NAME}_initial.png

echo "=== Setup complete ==="