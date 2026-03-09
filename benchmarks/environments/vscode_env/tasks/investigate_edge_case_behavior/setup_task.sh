#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Edge Case Investigation Task ==="

WORKSPACE_DIR="/home/ga/workspace/edge_case_investigation"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/utils"

# Create the buggy pricing utility
cat > "$WORKSPACE_DIR/utils/__init__.py" << 'EOF'
from .pricing import calculate_discount

__all__ = ['calculate_discount']
EOF

cat > "$WORKSPACE_DIR/utils/pricing.py" << 'EOF'
"""
Pricing utilities for e-commerce checkout system.
Customer reported negative prices appearing on checkout page.
"""

def calculate_discount(price, discount_percent):
    """
    Apply discount percentage to a price.
    
    Args:
        price: Original price
        discount_percent: Discount percentage (e.g., 10 for 10% off)
    
    Returns:
        Final price after discount
    """
    # Apply discount calculation
    discounted = price - (price * discount_percent / 100)
    return discounted
EOF

# Create test suite showing failures
cat > "$WORKSPACE_DIR/test_pricing.py" << 'EOF'
"""
Test suite for pricing utilities.
Multiple tests are failing with bizarre edge case behaviors.
"""

from utils.pricing import calculate_discount


def test_normal_discount():
    """Normal case: 20% off $100 should be $80"""
    result = calculate_discount(100, 20)
    assert result == 80, f"Expected 80, got {result}"
    print("✓ Normal discount test passed")


def test_negative_discount():
    """Edge case: negative discount should raise error or return original price"""
    result = calculate_discount(100, -10)
    print(f"Negative discount result: {result}")
    assert result >= 100, f"Negative discount produced {result}, expected >= 100"


def test_excessive_discount():
    """Edge case: >100% discount should be clamped or raise error"""
    result = calculate_discount(100, 150)
    print(f"Excessive discount (150%) result: {result}")
    assert result >= 0, f"Excessive discount produced negative price: {result}"


def test_string_price():
    """Edge case: string price should raise TypeError"""
    try:
        result = calculate_discount("100", 50)
        print(f"String price result: {result} (type: {type(result)})")
        # If we get here, type coercion happened unexpectedly
        assert isinstance(result, (int, float)), f"Result type unexpected: {type(result)}"
    except TypeError:
        print("✓ String price correctly raises TypeError")


def test_string_discount():
    """Edge case: string discount should raise TypeError"""
    try:
        result = calculate_discount(100, "50")
        print(f"String discount result: {result} (type: {type(result)})")
        assert isinstance(result, (int, float)), f"Result type unexpected: {type(result)}"
    except TypeError:
        print("✓ String discount correctly raises TypeError")


def test_zero_price():
    """Boundary case: zero price"""
    result = calculate_discount(0, 50)
    assert result == 0, f"Expected 0, got {result}"
    print("✓ Zero price test passed")


def test_zero_discount():
    """Boundary case: zero discount"""
    result = calculate_discount(100, 0)
    assert result == 100, f"Expected 100, got {result}"
    print("✓ Zero discount test passed")


def test_hundred_percent_discount():
    """Boundary case: 100% discount"""
    result = calculate_discount(100, 100)
    assert result == 0, f"Expected 0, got {result}"
    print("✓ 100% discount test passed")


if __name__ == "__main__":
    print("=" * 60)
    print("Running Pricing Utility Test Suite")
    print("=" * 60)
    
    tests = [
        ("Normal discount", test_normal_discount),
        ("Negative discount", test_negative_discount),
        ("Excessive discount (>100%)", test_excessive_discount),
        ("String price", test_string_price),
        ("String discount", test_string_discount),
        ("Zero price", test_zero_price),
        ("Zero discount", test_zero_discount),
        ("100% discount", test_hundred_percent_discount),
    ]
    
    passed = 0
    failed = 0
    
    for name, test_func in tests:
        print(f"\n--- Testing: {name} ---")
        try:
            test_func()
            passed += 1
        except AssertionError as e:
            print(f"✗ FAILED: {e}")
            failed += 1
        except Exception as e:
            print(f"✗ ERROR: {e}")
            failed += 1
    
    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)
EOF

# Create project README with context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Edge Case Investigation Task

## Background

A customer reported that checkout page is showing **negative prices** in certain situations. 
The QA team traced it to the `calculate_discount()` function in `utils/pricing.py`.

## Your Mission

**Investigate WHY the function fails for edge cases and document your findings.**

### Steps:

1. **Run the test suite** to see the failures: