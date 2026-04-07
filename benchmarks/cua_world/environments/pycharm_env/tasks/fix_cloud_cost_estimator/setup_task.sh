#!/bin/bash
echo "=== Setting up fix_cloud_cost_estimator task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/cloud_cost_estimator"

# Clean previous run
rm -rf "$PROJECT_DIR"
rm -f /tmp/fix_cloud_cost_estimator_result.json
rm -f /tmp/task_start_time

# Create directory structure
su - ga -c "mkdir -p $PROJECT_DIR/data $PROJECT_DIR/src $PROJECT_DIR/tests"

# --- 1. Data Files ---

# Pricing Catalog (JSON)
cat > "$PROJECT_DIR/data/pricing_catalog.json" << 'JSONEOF'
{
  "storage": {
    "us-east-1": {
      "standard": 0.023,
      "unit": "GiB"
    },
    "us-west-2": {
      "standard": 0.025,
      "unit": "GiB"
    }
  },
  "data_transfer_out": {
    "us-east-1": [
      {"limit": 10240, "price": 0.090},
      {"limit": 51200, "price": 0.085},
      {"limit": 153600, "price": 0.070},
      {"limit": null, "price": 0.050}
    ]
  }
}
JSONEOF

# Usage Logs (CSV)
# Note: Storage is in GB, Transfer in GB
cat > "$PROJECT_DIR/data/usage_logs.csv" << 'CSVEOF'
Date,Service,Region,Resource,Amount,Unit
2023-10-01,Storage,us-east-1,bucket-a,1000,GB
2023-10-01,DataTransfer,us-east-1,app-lb,55000,GB
2023-10-01,Storage,us-east-1a,bucket-b,500,GB
CSVEOF

# --- 2. Source Code (Buggy) ---

# src/__init__.py
touch "$PROJECT_DIR/src/__init__.py"

# src/utils.py
cat > "$PROJECT_DIR/src/utils.py" << 'PYEOF'
import json
import csv

def load_pricing(path):
    with open(path, 'r') as f:
        return json.load(f)

def load_usage(path):
    usage = []
    with open(path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            row['Amount'] = float(row['Amount'])
            usage.append(row)
    return usage
PYEOF

# src/estimator.py (Contains the 3 bugs)
cat > "$PROJECT_DIR/src/estimator.py" << 'PYEOF'
import math

def get_region_price(catalog, service, region):
    """
    Look up price for a service in a region.
    """
    if service == 'Storage':
        # BUG 3: Exact match only. Fails for 'us-east-1a' (AZ) vs 'us-east-1' (Region)
        if region in catalog['storage']:
            return catalog['storage'][region]['standard']
    elif service == 'DataTransfer':
        if region in catalog['data_transfer_out']:
            return catalog['data_transfer_out'][region]
    return None

def calculate_storage_cost(amount_gb, price_per_gib):
    """
    Calculate storage cost. 
    Input amount is in GB (10^9), Price is per GiB (2^30).
    """
    # BUG 1: Treats GB as equal to GiB.
    # Should be: amount_gib = amount_gb * (10**9) / (2**30)
    amount_gib = amount_gb 
    return amount_gib * price_per_gib

def calculate_transfer_cost(amount_gb, tiers):
    """
    Calculate tiered data transfer cost.
    Tiers structure: [{'limit': 10240, 'price': 0.09}, ...] (limit in GB)
    """
    remaining = amount_gb
    total_cost = 0.0
    
    # BUG 2: Tiered pricing logic is wrong.
    # It finds the tier the total amount falls into and applies that price to the WHOLE amount.
    # Instead of cumulative calculation.
    
    applied_price = 0.0
    
    # Wrong logic: find the single rate to apply
    for tier in tiers:
        limit = tier['limit']
        price = tier['price']
        
        if limit is None or amount_gb <= limit:
            applied_price = price
            break
            
    return amount_gb * applied_price

def estimate_total_daily_cost(usage_data, pricing_catalog):
    total_cost = 0.0
    
    for record in usage_data:
        service = record['Service']
        region = record['Region']
        amount = record['Amount']
        
        if service == 'Storage':
            price = get_region_price(pricing_catalog, service, region)
            if price:
                total_cost += calculate_storage_cost(amount, price)
                
        elif service == 'DataTransfer':
            tiers = get_region_price(pricing_catalog, service, region)
            if tiers:
                total_cost += calculate_transfer_cost(amount, tiers)
                
    return total_cost
PYEOF

# --- 3. Tests ---

# tests/__init__.py
touch "$PROJECT_DIR/tests/__init__.py"

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import sys
import os

# Add src to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../src')))
PYEOF

# tests/test_storage.py
cat > "$PROJECT_DIR/tests/test_storage.py" << 'PYEOF'
import pytest
from estimator import calculate_storage_cost

def test_storage_gb_to_gib_conversion():
    # 1000 GB = 1000 * 10^9 bytes
    # 1 GiB = 2^30 bytes = 1,073,741,824 bytes
    # 1000 GB = 931.32257... GiB
    # Price = $0.023/GiB
    # Expected cost = 931.32257 * 0.023 ~= 21.42
    
    amount_gb = 1000
    price = 0.023
    
    cost = calculate_storage_cost(amount_gb, price)
    
    # The buggy version returns 23.0 (1000 * 0.023)
    # The correct version should be around 21.42
    
    assert 21.40 < cost < 21.45, f"Expected cost ~21.42 (GB->GiB conversion), got {cost}"
PYEOF

# tests/test_transfer.py
cat > "$PROJECT_DIR/tests/test_transfer.py" << 'PYEOF'
import pytest
from estimator import calculate_transfer_cost

def test_tiered_pricing_cumulative():
    # Tiers:
    # 0 - 10 GB: $0.10
    # 10 - 50 GB: $0.08
    # 50+ GB: $0.05
    
    tiers = [
        {'limit': 10, 'price': 0.10},
        {'limit': 50, 'price': 0.08},
        {'limit': None, 'price': 0.05}
    ]
    
    # Test case: 60 GB total
    # First 10 GB @ 0.10 = $1.00
    # Next 40 GB @ 0.08 = $3.20
    # Last 10 GB @ 0.05 = $0.50
    # Total Expected = $4.70
    
    # Buggy logic does: 60 > 50, so use 0.05 rate. 60 * 0.05 = $3.00.
    
    amount = 60
    cost = calculate_transfer_cost(amount, tiers)
    
    assert abs(cost - 4.70) < 0.01, f"Expected cumulative cost $4.70, got {cost}"

def test_tiered_pricing_within_first_tier():
    tiers = [{'limit': 10, 'price': 0.10}, {'limit': None, 'price': 0.05}]
    amount = 5
    cost = calculate_transfer_cost(amount, tiers)
    assert abs(cost - 0.50) < 0.01
PYEOF

# tests/test_integration.py
cat > "$PROJECT_DIR/tests/test_integration.py" << 'PYEOF'
import pytest
from estimator import get_region_price

def test_region_lookup_with_az():
    # Catalog has 'us-east-1'
    catalog = {
        'storage': {
            'us-east-1': {'standard': 0.023}
        }
    }
    
    # Should handle 'us-east-1a' by stripping suffix or partial match
    price = get_region_price(catalog, 'Storage', 'us-east-1a')
    
    assert price == 0.023, "Failed to resolve 'us-east-1a' to 'us-east-1' price"

def test_region_lookup_exact():
    catalog = {
        'storage': {
            'us-east-1': {'standard': 0.023}
        }
    }
    price = get_region_price(catalog, 'Storage', 'us-east-1')
    assert price == 0.023
PYEOF

# requirements.txt
echo "pytest>=7.0" > "$PROJECT_DIR/requirements.txt"

# Record start time
date +%s > /tmp/task_start_time

# Open PyCharm
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "cloud_cost_estimator"

echo "=== Setup complete ==="