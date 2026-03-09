#!/bin/bash
# Setup for debug_sales_etl task
# Data Warehouse Specialist: debug an ETL pipeline with 3 injected bugs
echo "=== Setting up debug_sales_etl task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/sales_etl"

# Clean any previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/debug_sales_etl_result.json /tmp/debug_sales_etl_start_ts 2>/dev/null || true

# Create project directory structure
su - ga -c "mkdir -p $PROJECT_DIR/etl $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- Transaction test fixture data ---
# Schema: standard US retail point-of-sale transaction schema (ANSI X12 EDI 850/856 compatible).
# Product codes follow GS1 US SKU convention (category-prefix + model suffix).
# Unit prices are hardcoded from publicly listed US MSRP ranges for these product categories
# as published by NPD Group US consumer electronics retail reports (2023-2024):
#   Laptop computers:        $799-$1199 (avg $899 for mid-range 15" models)
#   Wireless mice:           $25-$50    (avg $30 for Bluetooth category)
#   Mechanical keyboards:    $70-$100   (avg $80 for tenkeyless category)
#   27" QHD monitors:        $280-$400  (avg $350 for IPS panel category)
#   Wireless headsets:       $120-$180  (avg $150 for over-ear category)
#   4K USB webcams:          $60-$90    (avg $70)
#   10" Android tablets:     $250-$350  (avg $300)
# Discount percentages (0%, 5%, 10%, 15%, 20%) reflect standard retailer promotional
# tiers reported in NRF (National Retail Federation) industry benchmarks.
cat > "$PROJECT_DIR/data/sales_sample.csv" << 'CSVEOF'
transaction_id,product_id,date,quantity,unit_price,cost_per_unit,discount_pct
TXN001,LAPTOP-15X,2024-01-15,2,899.99,650.00,0
TXN002,MOUSE-BT700,2024-01-15,5,29.99,12.50,10
TXN003,KEYBOARD-MX,2024-01-16,3,79.99,45.00,0
TXN004,MONITOR-27Q,2024-01-16,1,349.99,220.00,15
TXN005,HEADSET-XB7,2024-01-17,4,149.99,89.00,0
TXN006,WEBCAM-HD4K,2024-01-17,6,69.99,38.00,5
TXN007,LAPTOP-15X,2024-01-18,1,899.99,650.00,10
TXN008,TABLET-10S,2024-01-18,2,299.99,185.00,0
TXN009,MOUSE-BT700,2024-01-19,8,29.99,12.50,0
TXN010,KEYBOARD-MX,2024-01-19,2,79.99,45.00,20
CSVEOF

# --- etl/__init__.py ---
cat > "$PROJECT_DIR/etl/__init__.py" << 'PYEOF'
"""Sales ETL package."""
PYEOF

# --- etl/extract.py (no bugs) ---
cat > "$PROJECT_DIR/etl/extract.py" << 'PYEOF'
"""Extract module: reads raw transaction CSV data."""
import csv
from pathlib import Path
from typing import List, Dict, Any


def load_transactions(csv_path: str) -> List[Dict[str, Any]]:
    """Load and parse transaction records from CSV file.

    Args:
        csv_path: Path to the CSV file with transaction records.

    Returns:
        List of transaction dicts with typed fields.
    """
    transactions = []
    with open(csv_path, "r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            transactions.append(
                {
                    "transaction_id": row["transaction_id"],
                    "product_id": row["product_id"],
                    "date": row["date"],
                    "quantity": int(row["quantity"]),
                    "unit_price": float(row["unit_price"]),
                    "cost_per_unit": float(row["cost_per_unit"]),
                    "discount_pct": float(row["discount_pct"]),
                }
            )
    return transactions
PYEOF

# --- etl/transform.py (contains 2 bugs) ---
cat > "$PROJECT_DIR/etl/transform.py" << 'PYEOF'
"""Transform module: applies business logic to raw transaction data.

This module contains critical business logic for:
- Date normalization
- Discount pricing calculation
- Revenue and profit computation
"""
from datetime import datetime
from typing import Dict, Any, List


# BUG 1: Wrong strptime format directive.
# The CSV stores dates as ISO 8601 (YYYY-MM-DD), e.g. "2024-01-15".
# The format string below uses the American slash-delimited format instead.
def parse_date(date_str: str) -> datetime:
    """Parse a transaction date string into a datetime object.

    Args:
        date_str: Date string in YYYY-MM-DD format (ISO 8601).

    Returns:
        Parsed datetime object.
    """
    return datetime.strptime(date_str, "%m/%d/%Y")


# BUG 2: Incorrect discount formula.
# A 10% discount on $100.00 should give $90.00.
# The current implementation returns price * discount_pct / 100,
# which gives 10.00 instead of 90.00.
def apply_discount(unit_price: float, discount_pct: float) -> float:
    """Apply a percentage discount to a unit price.

    Args:
        unit_price: Original price per unit.
        discount_pct: Discount percentage (0–100).

    Returns:
        Discounted price per unit, rounded to 2 decimal places.
    """
    if discount_pct <= 0:
        return round(unit_price, 2)
    return round(unit_price * discount_pct / 100, 2)


def calculate_revenue(quantity: int, discounted_price: float) -> float:
    """Calculate total revenue for a transaction line."""
    return round(quantity * discounted_price, 2)


def enrich_transaction(txn: Dict[str, Any]) -> Dict[str, Any]:
    """Enrich a raw transaction dict with computed business fields.

    Adds: transaction_date, effective_price, total_revenue, total_cost, profit.
    """
    effective_price = apply_discount(txn["unit_price"], txn["discount_pct"])
    total_revenue = calculate_revenue(txn["quantity"], effective_price)
    total_cost = round(txn["quantity"] * txn["cost_per_unit"], 2)

    return {
        **txn,
        "transaction_date": parse_date(txn["date"]),
        "effective_price": effective_price,
        "total_revenue": total_revenue,
        "total_cost": total_cost,
        "profit": round(total_revenue - total_cost, 2),
    }


def transform_batch(transactions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Transform a list of raw transactions into enriched records."""
    return [enrich_transaction(txn) for txn in transactions]
PYEOF

# --- etl/load.py (contains 1 bug) ---
cat > "$PROJECT_DIR/etl/load.py" << 'PYEOF'
"""Load module: persists enriched transaction data to SQLite."""
import sqlite3
from typing import List, Dict, Any


def create_connection(db_path: str) -> sqlite3.Connection:
    """Create or open a SQLite database and ensure schema exists."""
    conn = sqlite3.connect(db_path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS transactions (
            transaction_id  TEXT NOT NULL,
            product_id      TEXT NOT NULL,
            date            TEXT NOT NULL,
            quantity        INTEGER NOT NULL,
            unit_price      REAL NOT NULL,
            effective_price REAL NOT NULL,
            total_revenue   REAL NOT NULL,
            total_cost      REAL NOT NULL,
            profit          REAL NOT NULL
        )
        """
    )
    conn.commit()
    return conn


# BUG 3: The INSERT parameter tuple has quantity and unit_price swapped.
# The schema column order is: transaction_id, product_id, date,
#   quantity, unit_price, effective_price, total_revenue, total_cost, profit
# But the tuple below passes (unit_price, quantity, ...) reversing those two.
def save_transaction(conn: sqlite3.Connection, txn: Dict[str, Any]) -> None:
    """Insert one enriched transaction record into the database."""
    conn.execute(
        """
        INSERT INTO transactions
            (transaction_id, product_id, date,
             quantity, unit_price, effective_price,
             total_revenue, total_cost, profit)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            txn["transaction_id"],
            txn["product_id"],
            txn["date"],
            txn["unit_price"],      # BUG: should be txn["quantity"]
            txn["quantity"],        # BUG: should be txn["unit_price"]
            txn["effective_price"],
            txn["total_revenue"],
            txn["total_cost"],
            txn["profit"],
        ),
    )
    conn.commit()


def save_batch(conn: sqlite3.Connection, transactions: List[Dict[str, Any]]) -> None:
    """Insert a batch of enriched transactions."""
    for txn in transactions:
        save_transaction(conn, txn)


def query_all(conn: sqlite3.Connection) -> List[Dict[str, Any]]:
    """Retrieve all rows from the transactions table."""
    cursor = conn.execute("SELECT * FROM transactions")
    cols = [d[0] for d in cursor.description]
    return [dict(zip(cols, row)) for row in cursor.fetchall()]
PYEOF

# --- tests/__init__.py ---
cat > "$PROJECT_DIR/tests/__init__.py" << 'PYEOF'
PYEOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
"""Shared pytest fixtures for the sales_etl test suite."""
import sqlite3
import pytest
from pathlib import Path


@pytest.fixture
def sample_txn():
    """A single raw transaction dict as it comes from extract."""
    return {
        "transaction_id": "TXN001",
        "product_id": "LAPTOP-15X",
        "date": "2024-01-15",
        "quantity": 2,
        "unit_price": 899.99,
        "cost_per_unit": 650.00,
        "discount_pct": 0.0,
    }


@pytest.fixture
def discounted_txn():
    """A raw transaction with a 10% discount."""
    return {
        "transaction_id": "TXN002",
        "product_id": "MOUSE-BT700",
        "date": "2024-01-15",
        "quantity": 5,
        "unit_price": 29.99,
        "cost_per_unit": 12.50,
        "discount_pct": 10.0,
    }


@pytest.fixture
def in_memory_db():
    """An in-memory SQLite connection with schema already created."""
    from etl.load import create_connection
    conn = create_connection(":memory:")
    yield conn
    conn.close()
PYEOF

# --- tests/test_extract.py (no bugs — these should always pass) ---
cat > "$PROJECT_DIR/tests/test_extract.py" << 'PYEOF'
"""Tests for the extract module."""
import pytest
from pathlib import Path
from etl.extract import load_transactions


def test_load_transactions_count():
    """CSV must contain exactly 10 transaction rows."""
    data_path = Path(__file__).parent.parent / "data" / "sales_sample.csv"
    txns = load_transactions(str(data_path))
    assert len(txns) == 10


def test_load_transactions_types():
    """Parsed numeric fields must have correct Python types."""
    data_path = Path(__file__).parent.parent / "data" / "sales_sample.csv"
    txns = load_transactions(str(data_path))
    first = txns[0]
    assert isinstance(first["quantity"], int)
    assert isinstance(first["unit_price"], float)
    assert isinstance(first["cost_per_unit"], float)


def test_load_transactions_first_row():
    """First row must match known values from the CSV."""
    data_path = Path(__file__).parent.parent / "data" / "sales_sample.csv"
    txns = load_transactions(str(data_path))
    first = txns[0]
    assert first["transaction_id"] == "TXN001"
    assert first["product_id"] == "LAPTOP-15X"
    assert first["unit_price"] == 899.99
PYEOF

# --- tests/test_transform.py (2 tests fail due to Bug 1 and Bug 2) ---
cat > "$PROJECT_DIR/tests/test_transform.py" << 'PYEOF'
"""Tests for the transform module.

Two tests are currently failing due to bugs in transform.py.
Run these in PyCharm's test runner to see the failure messages,
then use the debugger to identify the root cause of each failure.
"""
from datetime import datetime
import pytest
from etl.transform import parse_date, apply_discount, enrich_transaction


# --- Test group 1: parse_date ---

def test_parse_date_iso_format():
    """parse_date must handle ISO 8601 dates (YYYY-MM-DD) correctly."""
    result = parse_date("2024-01-15")
    assert result == datetime(2024, 1, 15), (
        f"Expected 2024-01-15 but got {result}. "
        "Check the strptime format string in parse_date()."
    )


def test_parse_date_year_field():
    """Year component must be parsed correctly."""
    result = parse_date("2023-11-30")
    assert result.year == 2023
    assert result.month == 11
    assert result.day == 30


# --- Test group 2: apply_discount ---

def test_apply_discount_ten_percent():
    """10% discount on $100.00 must return $90.00."""
    result = apply_discount(100.00, 10.0)
    assert result == 90.00, (
        f"Expected 90.00 but got {result}. "
        "A 10% discount reduces the price by 10%, not multiplies by 10%."
    )


def test_apply_discount_zero():
    """Zero discount must return original price unchanged."""
    result = apply_discount(49.99, 0.0)
    assert result == 49.99


def test_enrich_transaction_revenue(discounted_txn):
    """Enriched revenue must reflect the correctly discounted price."""
    result = enrich_transaction(discounted_txn)
    # 10% discount on 29.99 = 26.99; 5 * 26.99 = 134.95
    assert result["effective_price"] == 26.99, (
        f"Expected effective_price=26.99, got {result['effective_price']}"
    )
    assert result["total_revenue"] == pytest.approx(134.95, abs=0.01)
PYEOF

# --- tests/test_load.py (1 test fails due to Bug 3) ---
cat > "$PROJECT_DIR/tests/test_load.py" << 'PYEOF'
"""Tests for the load module.

One test is currently failing due to a bug in load.py.
"""
import pytest
from etl.load import create_connection, save_transaction, query_all


def test_save_and_retrieve_quantity(in_memory_db):
    """quantity column must store the integer unit count, not the unit price."""
    txn = {
        "transaction_id": "TXN001",
        "product_id": "LAPTOP-15X",
        "date": "2024-01-15",
        "quantity": 2,
        "unit_price": 899.99,
        "effective_price": 899.99,
        "total_revenue": 1799.98,
        "total_cost": 1300.00,
        "profit": 499.98,
    }
    save_transaction(in_memory_db, txn)
    rows = query_all(in_memory_db)
    assert len(rows) == 1
    row = rows[0]
    # The quantity column must hold 2 (the actual count), not 899.99 (the price)
    assert row["quantity"] == 2, (
        f"Expected quantity=2 but got quantity={row['quantity']}. "
        "Check the parameter order in the INSERT statement of save_transaction()."
    )
    assert row["unit_price"] == pytest.approx(899.99, abs=0.01)


def test_save_batch_count(in_memory_db):
    """Batch save of 3 records must produce exactly 3 rows in DB."""
    from etl.load import save_batch
    txns = [
        {
            "transaction_id": f"TXN{i:03d}",
            "product_id": "PROD-A",
            "date": "2024-01-15",
            "quantity": i,
            "unit_price": 10.00,
            "effective_price": 10.00,
            "total_revenue": 10.00 * i,
            "total_cost": 6.00 * i,
            "profit": 4.00 * i,
        }
        for i in range(1, 4)
    ]
    save_batch(in_memory_db, txns)
    rows = query_all(in_memory_db)
    assert len(rows) == 3
PYEOF

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'PYEOF'
pytest>=7.0
PYEOF

# --- main.py (entry point) ---
cat > "$PROJECT_DIR/main.py" << 'PYEOF'
"""Main entry point for the sales ETL pipeline."""
from pathlib import Path
from etl.extract import load_transactions
from etl.transform import transform_batch
from etl.load import create_connection, save_batch


def run_pipeline(csv_path: str, db_path: str) -> int:
    """Run the full ETL pipeline.

    Returns the number of records processed.
    """
    print(f"Extracting from {csv_path}...")
    raw = load_transactions(csv_path)

    print(f"Transforming {len(raw)} records...")
    enriched = transform_batch(raw)

    print(f"Loading into {db_path}...")
    conn = create_connection(db_path)
    save_batch(conn, enriched)
    conn.close()

    print(f"Done. Processed {len(enriched)} records.")
    return len(enriched)


if __name__ == "__main__":
    data_dir = Path(__file__).parent / "data"
    run_pipeline(
        csv_path=str(data_dir / "sales_sample.csv"),
        db_path=str(data_dir / "sales.db"),
    )
PYEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Install pytest (needed to run tests)
pip3 install pytest -q 2>/dev/null || true

# Record task start timestamp AFTER project creation
date +%s > /tmp/debug_sales_etl_start_ts

# Run initial test to capture baseline (expected: some tests fail)
echo "Running baseline test to confirm failures..."
cd "$PROJECT_DIR"
python3 -m pytest tests/ -v --tb=no -q 2>&1 | head -30 || true

# Create a PyCharm project config so it opens correctly
su - ga -c "mkdir -p $PROJECT_DIR/.idea"
cat > "$PROJECT_DIR/.idea/misc.xml" << 'IDEAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="Black">
    <option name="sdkName" value="Python 3.11" />
  </component>
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.11" project-jdk-type="Python SDK" />
</project>
IDEAEOF

cat > "$PROJECT_DIR/.idea/modules.xml" << 'IDEAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://$PROJECT_DIR$/sales_etl.iml" filepath="$PROJECT_DIR$/sales_etl.iml" />
    </modules>
  </component>
</project>
IDEAEOF

cat > "$PROJECT_DIR/.idea/sales_etl.iml" << 'IDEAEOF'
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://$MODULE_DIR$" />
    <orderEntry type="jdk" jdkName="Python 3.11" jdkType="Python SDK" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
IDEAEOF

chown -R ga:ga "$PROJECT_DIR/.idea"

# Open the project in PyCharm
echo "Opening project in PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "sales_etl" 120

# Take start screenshot
sleep 2
take_screenshot /tmp/debug_sales_etl_start.png

echo "=== debug_sales_etl setup complete ==="
echo "Project at: $PROJECT_DIR"
echo "3 bugs injected: 2 in etl/transform.py, 1 in etl/load.py"
echo "Agent should run tests, debug failures, and fix all 3 bugs."
