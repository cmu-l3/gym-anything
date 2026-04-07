#!/bin/bash
set -e

echo "=== Setting up Fix Broken Test Suite Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/inventory_system"
sudo -u ga mkdir -p "$WORKSPACE_DIR/inventory"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# ─────────────────────────────────────────────────────────────
# 1. Generate Correct Library Code (MUST NOT BE MODIFIED)
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/inventory/__init__.py" << 'EOF'
# Inventory Package
EOF

cat > "$WORKSPACE_DIR/inventory/models.py" << 'EOF'
from dataclasses import dataclass

@dataclass
class Product:
    id: str
    name: str
    price: float

@dataclass
class Warehouse:
    id: str
    location: str
EOF

cat > "$WORKSPACE_DIR/inventory/stock_manager.py" << 'EOF'
import threading

class StockManager:
    def __init__(self):
        self.stock = {}
        self.lock = threading.Lock()

    def add_stock(self, warehouse_id, product_id, qty):
        with self.lock:
            key = f"{warehouse_id}_{product_id}"
            self.stock[key] = self.stock.get(key, 0) + qty

    def remove_stock(self, warehouse_id, product_id, qty):
        with self.lock:
            key = f"{warehouse_id}_{product_id}"
            if self.stock.get(key, 0) < qty:
                raise ValueError("Insufficient stock")
            self.stock[key] -= qty

    def transfer(self, src_wh, dst_wh, product_id, qty):
        with self.lock:
            src_key = f"{src_wh}_{product_id}"
            dst_key = f"{dst_wh}_{product_id}"
            if self.stock.get(src_key, 0) < qty:
                raise ValueError("Insufficient stock")
            self.stock[src_key] -= qty
            self.stock[dst_key] = self.stock.get(dst_key, 0) + qty

    def get_stock(self, warehouse_id, product_id):
        with self.lock:
            return self.stock.get(f"{warehouse_id}_{product_id}", 0)
EOF

cat > "$WORKSPACE_DIR/inventory/pricing.py" << 'EOF'
def calculate_discount(price, discount_rate):
    """Calculate discounted price."""
    return price * (1.0 - discount_rate)
EOF

cat > "$WORKSPACE_DIR/inventory/alerts.py" << 'EOF'
def _dispatch_email(to_address, subject, body):
    """Internal method to send email."""
    print(f"Sending email to {to_address}: {subject}")
    return True

def check_low_stock(stock_level, threshold=10):
    """Check stock and alert if low."""
    if stock_level < threshold:
        _dispatch_email("admin@warehouse.com", "Low Stock Alert", f"Stock is at {stock_level}")
        return True
    return False
EOF

cat > "$WORKSPACE_DIR/inventory/reports.py" << 'EOF'
import datetime

def generate_report():
    """Generate a daily inventory report string."""
    today = datetime.datetime.now().strftime('%Y-%m-%d')
    return f"Inventory Report generated on {today}"
EOF

# ─────────────────────────────────────────────────────────────
# 2. Generate Buggy Test Suite (Agent must fix these)
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/tests/__init__.py" << 'EOF'
EOF

cat > "$WORKSPACE_DIR/tests/test_stock_operations.py" << 'EOF'
import unittest
import pytest
from inventory.stock_manager import StockManager

class TestStockOperations(unittest.TestCase):
    def test_boundary_stock_removal(self):
        sm = StockManager()
        # BUG 1: Adding 10, but trying to test boundary removal of 100
        sm.add_stock("WH1", "ITEM", 10)
        
        # Test boundary removal (should succeed without ValueError)
        sm.remove_stock("WH1", "ITEM", 10)
        
        # Assert empty
        self.assertEqual(sm.get_stock("WH1", "ITEM"), 0)
EOF

cat > "$WORKSPACE_DIR/tests/test_pricing.py" << 'EOF'
import unittest
from inventory.pricing import calculate_discount

class TestPricing(unittest.TestCase):
    def test_calculate_discount(self):
        price = 100.0
        discount = 0.1
        result = calculate_discount(price, discount)
        # BUG 2: Exact float equality. Will fail on values like 10.10
        self.assertEqual(result, 90.0)
EOF

cat > "$WORKSPACE_DIR/tests/test_alerts.py" << 'EOF'
import unittest
from unittest.mock import patch
from inventory.alerts import check_low_stock

class TestAlerts(unittest.TestCase):
    # BUG 3: Patching a non-existent method, so assert_not_called always passes
    @patch("inventory.alerts.send_notification", create=True)
    def test_no_alert_on_normal_stock(self, mock_send):
        check_low_stock(15)  # 15 is > threshold 10
        mock_send.assert_not_called()
EOF

cat > "$WORKSPACE_DIR/tests/test_transfers.py" << 'EOF'
import unittest
from inventory.stock_manager import StockManager

class TestTransfers(unittest.TestCase):
    def test_transfer_stock(self):
        sm = StockManager()
        sm.add_stock("SRC", "ITEM", 100)
        
        sm.transfer("SRC", "DST", "ITEM", 50)
        
        # BUG 4: Only checks destination received it, missing source deduction check
        self.assertEqual(sm.get_stock("DST", "ITEM"), 50)
EOF

cat > "$WORKSPACE_DIR/tests/test_reports.py" << 'EOF'
import unittest
import datetime
from inventory.reports import generate_report

class TestReports(unittest.TestCase):
    def test_report_format(self):
        result = generate_report()
        # BUG 5: Brittle test relying on current system time
        today = datetime.datetime.now().strftime('%Y-%m-%d')
        self.assertIn(today, result)
EOF

cat > "$WORKSPACE_DIR/tests/test_concurrent_access.py" << 'EOF'
import unittest
import threading
from inventory.stock_manager import StockManager

class TestConcurrency(unittest.TestCase):
    def test_concurrent_add(self):
        sm = StockManager()
        
        threads = []
        for _ in range(100):
            t = threading.Thread(target=sm.add_stock, args=("WH1", "ITEM", 1))
            threads.append(t)
            
        for t in threads:
            t.start()
            
        for t in threads:
            # BUG 6: Non-blocking join means main thread doesn't wait
            t.join(timeout=0)
            
        # Coincidentally passes because >= 0 is always true
        self.assertGreaterEqual(sm.get_stock("WH1", "ITEM"), 0)
EOF

# ─────────────────────────────────────────────────────────────
# 3. Hidden Buggy Variants for Verifier (Root access only)
# ─────────────────────────────────────────────────────────────
HIDDEN_DIR="/var/lib/inventory_buggy"
mkdir -p "$HIDDEN_DIR"
chmod 700 "$HIDDEN_DIR"

# Variant 1: Fails if removing >= 100
mkdir -p "$HIDDEN_DIR/variant1"
cat > "$HIDDEN_DIR/variant1/stock_manager.py" << 'EOF'
import threading
class StockManager:
    def __init__(self): self.stock = {}; self.lock = threading.Lock()
    def add_stock(self, w, p, q): self.stock[f"{w}_{p}"] = self.stock.get(f"{w}_{p}", 0) + q
    def remove_stock(self, w, p, q):
        if q >= 100: raise ValueError("Limit exceeded")
        self.stock[f"{w}_{p}"] -= q
    def get_stock(self, w, p): return self.stock.get(f"{w}_{p}", 0)
EOF

# Variant 2: Totally wrong discount math
mkdir -p "$HIDDEN_DIR/variant2"
cat > "$HIDDEN_DIR/variant2/pricing.py" << 'EOF'
def calculate_discount(price, discount_rate): return price * discount_rate
EOF

# Variant 3: Always alerts
mkdir -p "$HIDDEN_DIR/variant3"
cat > "$HIDDEN_DIR/variant3/alerts.py" << 'EOF'
def _dispatch_email(to, sub, body): pass
def check_low_stock(stock_level, threshold=10):
    _dispatch_email("admin@warehouse.com", "Alert", "Always alerts")
    return True
EOF

# Variant 4: Doesn't subtract from SRC
mkdir -p "$HIDDEN_DIR/variant4"
cat > "$HIDDEN_DIR/variant4/stock_manager.py" << 'EOF'
import threading
class StockManager:
    def __init__(self): self.stock = {}; self.lock = threading.Lock()
    def add_stock(self, w, p, q): self.stock[f"{w}_{p}"] = self.stock.get(f"{w}_{p}", 0) + q
    def transfer(self, src, dst, p, q):
        self.stock[f"{dst}_{p}"] = self.stock.get(f"{dst}_{p}", 0) + q
    def get_stock(self, w, p): return self.stock.get(f"{w}_{p}", 0)
EOF

# Variant 5: Hardcoded to Jan 1st
mkdir -p "$HIDDEN_DIR/variant5"
cat > "$HIDDEN_DIR/variant5/reports.py" << 'EOF'
import datetime
def generate_report(): return f"Inventory Report generated on {datetime.datetime.now().year}-01-01"
EOF

# Variant 6: No lock
mkdir -p "$HIDDEN_DIR/variant6"
cat > "$HIDDEN_DIR/variant6/stock_manager.py" << 'EOF'
import time
class StockManager:
    def __init__(self): self.stock = {}
    def add_stock(self, w, p, q):
        v = self.stock.get(f"{w}_{p}", 0)
        time.sleep(0.001)
        self.stock[f"{w}_{p}"] = v + q
    def get_stock(self, w, p): return self.stock.get(f"{w}_{p}", 0)
EOF

# ─────────────────────────────────────────────────────────────
# 4. Final Setup
# ─────────────────────────────────────────────────────────────

# Install dependencies
pip install pytest freezegun pytest-json-report > /dev/null 2>&1

chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode opens the workspace
echo "Starting VSCode..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
sleep 5

# Focus and maximize VSCode
WID=$(wmctrl -l | grep -i 'Visual Studio Code' | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    wmctrl -ia "$WID" 2>/dev/null || true
    wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="