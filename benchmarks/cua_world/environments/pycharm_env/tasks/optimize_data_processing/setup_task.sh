#!/bin/bash
set -e
echo "=== Setting up optimize_data_processing task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/data_processing"
mkdir -p "$PROJECT_DIR/processing"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# Clean up any previous run
rm -f /tmp/optimize_task_result.json 2>/dev/null || true
rm -f /tmp/optimize_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/optimize_start_ts

# 1. Create Data (Real-world retail transaction schema)
cat > "$PROJECT_DIR/data/transactions_sample.csv" << 'CSVEOF'
transaction_id,customer_id,product_sku,category,quantity,unit_price,discount_pct,timestamp
TXN001,CUST001,ELEC-LAPTOP-01,Electronics,1,1200.00,0.0,2023-10-01T10:00:00
TXN002,CUST002,HOME-BLENDER-05,Home,1,45.50,0.1,2023-10-01T10:05:00
TXN003,CUST001,ELEC-MOUSE-02,Electronics,2,25.00,0.0,2023-10-01T10:15:00
TXN004,CUST003,CLOTH-TSHIRT-01,Clothing,5,15.00,0.2,2023-10-01T10:20:00
TXN005,CUST002,HOME-LAMP-01,Home,2,30.00,0.0,2023-10-01T10:30:00
TXN006,CUST004,GROC-MILK-01,Grocery,4,3.50,0.0,2023-10-01T10:45:00
TXN007,CUST001,ELEC-LAPTOP-01,Electronics,1,1200.00,0.0,2023-10-01T10:00:00
TXN008,CUST005,BOOKS-PY-01,Books,1,45.00,0.0,2023-10-01T11:00:00
CSVEOF

# 2. Create Implementation Files (Slow O(n^2) versions)

# dedup.py - Slow nested loop
cat > "$PROJECT_DIR/processing/dedup.py" << 'PYEOF'
from typing import List, Dict, Any

def deduplicate_records(records: List[Dict[str, Any]], key_field: str) -> List[Dict[str, Any]]:
    """
    Remove duplicate records based on a specific key field.
    Keeps the first occurrence of any key.
    
    Args:
        records: List of dictionaries representing records
        key_field: Field name to check for uniqueness
        
    Returns:
        List of unique records
    """
    result = []
    # PERF ISSUE: Nested loop makes this O(n^2)
    for i, record in enumerate(records):
        is_duplicate = False
        for prev in result:
            if prev.get(key_field) == record.get(key_field):
                is_duplicate = True
                break
        if not is_duplicate:
            result.append(record)
    return result
PYEOF

# aggregate.py - Slow repeated scans
cat > "$PROJECT_DIR/processing/aggregate.py" << 'PYEOF'
from typing import List, Dict, Any

def aggregate_by_category(records: List[Dict[str, Any]], group_field: str, value_field: str) -> Dict[str, float]:
    """
    Sum the values of value_field grouped by group_field.
    
    Args:
        records: List of transaction records
        group_field: Field to group by (e.g., 'category')
        value_field: Field to sum (e.g., 'quantity')
        
    Returns:
        Dictionary mapping group names to totals
    """
    # First pass: find unique groups
    groups = []
    for r in records:
        val = r.get(group_field)
        if val not in groups:
            groups.append(val)
            
    # Second pass: iterate groups and scan records for each group
    # PERF ISSUE: O(groups * records) ~ O(n^2) if unique groups scale with n
    result = {}
    for g in groups:
        total = 0.0
        for r in records:
            if r.get(group_field) == g:
                total += float(r.get(value_field, 0))
        result[g] = total
    return result
PYEOF

# topk.py - Slow bubble sort
cat > "$PROJECT_DIR/processing/topk.py" << 'PYEOF'
from typing import List, Dict, Any

def top_k_by_value(records: List[Dict[str, Any]], value_field: str, k: int) -> List[Dict[str, Any]]:
    """
    Return the top k records with the highest value in value_field.
    
    Args:
        records: List of records
        value_field: Field to sort by
        k: Number of records to return
        
    Returns:
        Top k records sorted descending
    """
    # PERF ISSUE: Manual Bubble Sort is O(n^2)
    # Python's list.sort() or sorted() is O(n log n), heapq is O(n log k)
    sorted_records = list(records)
    n = len(sorted_records)
    
    for i in range(n):
        for j in range(0, n - i - 1):
            val1 = float(sorted_records[j].get(value_field, 0))
            val2 = float(sorted_records[j + 1].get(value_field, 0))
            if val1 < val2:
                # Swap
                sorted_records[j], sorted_records[j + 1] = sorted_records[j + 1], sorted_records[j]
                
    return sorted_records[:k]
PYEOF

# join.py - Slow nested loop join
cat > "$PROJECT_DIR/processing/join.py" << 'PYEOF'
from typing import List, Dict, Any

def inner_join(left: List[Dict], right: List[Dict], left_key: str, right_key: str) -> List[Dict]:
    """
    Perform an inner join between two lists of dictionaries.
    
    Args:
        left: Left dataset
        right: Right dataset
        left_key: Join key in left dataset
        right_key: Join key in right dataset
        
    Returns:
        List of merged dictionaries
    """
    result = []
    # PERF ISSUE: Nested loop join is O(n * m)
    for l_rec in left:
        for r_rec in right:
            if l_rec.get(left_key) == r_rec.get(right_key):
                # Merge records
                merged = {}
                merged.update(l_rec)
                merged.update(r_rec)
                result.append(merged)
    return result
PYEOF

# processing/__init__.py
touch "$PROJECT_DIR/processing/__init__.py"

# 3. Create Tests

# tests/conftest.py - Data generation fixtures
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import csv
import random
import os
from typing import List, Dict, Any

DATA_PATH = os.path.join(os.path.dirname(__file__), '../data/transactions_sample.csv')

@pytest.fixture
def sample_data() -> List[Dict[str, Any]]:
    """Load small sample data from CSV."""
    data = []
    if os.path.exists(DATA_PATH):
        with open(DATA_PATH, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # Type conversion
                row['quantity'] = int(row['quantity'])
                row['unit_price'] = float(row['unit_price'])
                row['discount_pct'] = float(row['discount_pct'])
                data.append(row)
    return data

@pytest.fixture
def large_data() -> List[Dict[str, Any]]:
    """Generate 50,000 records for performance testing."""
    # Deterministic generation
    random.seed(42)
    data = []
    categories = ['Electronics', 'Home', 'Clothing', 'Books', 'Grocery']
    
    for i in range(50000):
        data.append({
            'transaction_id': f'TXN{i}',
            'customer_id': f'CUST{i % 1000}',  # 1000 unique customers
            'product_sku': f'PROD{i % 500}',   # 500 unique products
            'category': categories[i % 5],
            'quantity': random.randint(1, 10),
            'unit_price': random.uniform(5.0, 500.0),
            'discount_pct': random.choice([0.0, 0.1, 0.2]),
            'timestamp': '2023-10-01T10:00:00'
        })
    return data
PYEOF

# tests/test_correctness.py - Functional verification
cat > "$PROJECT_DIR/tests/test_correctness.py" << 'PYEOF'
import pytest
from processing.dedup import deduplicate_records
from processing.aggregate import aggregate_by_category
from processing.topk import top_k_by_value
from processing.join import inner_join

def test_dedup_correctness(sample_data):
    """TXN007 is a duplicate of TXN001 (same transaction_id)."""
    result = deduplicate_records(sample_data, 'transaction_id')
    assert len(result) == 7  # 8 rows total, 1 duplicate
    # Ensure order preserved (TXN001 kept, TXN007 removed)
    assert result[0]['transaction_id'] == 'TXN001'

def test_aggregate_correctness(sample_data):
    """Sum quantity by category."""
    # Electronics: 1 (TXN1) + 2 (TXN3) + 1 (TXN7) = 4
    result = aggregate_by_category(sample_data, 'category', 'quantity')
    assert result['Electronics'] == 4
    assert result['Home'] == 3  # 1 + 2

def test_topk_correctness(sample_data):
    """Top 2 expensive items."""
    result = top_k_by_value(sample_data, 'unit_price', 2)
    assert len(result) == 2
    assert result[0]['unit_price'] == 1200.0
    assert result[1]['unit_price'] == 1200.0

def test_join_correctness():
    left = [{'id': 1, 'name': 'A'}, {'id': 2, 'name': 'B'}]
    right = [{'uid': 1, 'role': 'Admin'}, {'uid': 3, 'role': 'User'}]
    
    result = inner_join(left, right, 'id', 'uid')
    assert len(result) == 1
    assert result[0]['name'] == 'A'
    assert result[0]['role'] == 'Admin'
PYEOF

# tests/test_performance.py - Timeout tests
cat > "$PROJECT_DIR/tests/test_performance.py" << 'PYEOF'
import pytest
import time
from processing.dedup import deduplicate_records
from processing.aggregate import aggregate_by_category
from processing.topk import top_k_by_value
from processing.join import inner_join

# Threshold: 2.0 seconds (Optimized code takes ~0.1s, Slow code takes >10s)
PERF_THRESHOLD = 2.0

def test_perf_dedup(large_data):
    """Deduplication should be O(n)."""
    start = time.time()
    # Using customer_id creates many duplicates (50k records, 1k unique)
    deduplicate_records(large_data, 'customer_id')
    duration = time.time() - start
    assert duration < PERF_THRESHOLD, f"Dedup too slow: {duration:.2f}s"

def test_perf_aggregate(large_data):
    """Aggregation should be O(n)."""
    start = time.time()
    aggregate_by_category(large_data, 'category', 'unit_price')
    duration = time.time() - start
    assert duration < PERF_THRESHOLD, f"Aggregate too slow: {duration:.2f}s"

def test_perf_topk(large_data):
    """Top-K should be O(n log k) or O(n log n)."""
    start = time.time()
    top_k_by_value(large_data, 'unit_price', 100)
    duration = time.time() - start
    assert duration < PERF_THRESHOLD, f"TopK too slow: {duration:.2f}s"

def test_perf_join():
    """Join should be O(n + m)."""
    # 5000 records each side
    left = [{'id': i, 'val': i} for i in range(5000)]
    right = [{'uid': i, 'meta': i} for i in range(5000)]
    
    start = time.time()
    inner_join(left, right, 'id', 'uid')
    duration = time.time() - start
    assert duration < PERF_THRESHOLD, f"Join too slow: {duration:.2f}s"
PYEOF

# 4. requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQEOF'
pytest>=7.0
REQEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Wait for PyCharm (from task_utils)
# This assumes the base image starts PyCharm or the user starts it.
# The previous `setup_pycharm.sh` script usually starts it.
# We'll just ensure the window is ready.

echo "Waiting for PyCharm..."
for i in {1..30}; do
    if wmctrl -l | grep -qi "PyCharm"; then
        break
    fi
    sleep 1
done

# Open the project
su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /dev/null 2>&1 &"

# Maximize
sleep 10
DISPLAY=:1 wmctrl -r "PyCharm" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Setup complete ==="